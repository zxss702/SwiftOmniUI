// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "Relay.h"

#include <algorithm>
#include <array>
#include <deque>
#include <io.h>
#include <mutex>
#include <string_view>

namespace swiftomniui {
    namespace {
        // Retain startup, a compact state history and the recent bounded tail.
        // Nonfatal interactions must reach the file too, not just crash dumps.
        struct LayoutDiagnostics {
            static constexpr size_t capacity = 4096;
            std::mutex lock;
            std::array<std::string, capacity> recent;
            std::deque<std::string> states;
            std::deque<std::string> presentations;
            std::deque<std::string> allocations;
            size_t next = 0;
            uint64_t sequence = 0;
            ULONGLONG started = GetTickCount64();
            ULONGLONG savedAt = started;
            ULONGLONG prefixFlushedAt = started;
            uint64_t savedSequence = 0;
            int64_t tailOffset = -1;
            FILE *file = nullptr;
            PTP_TIMER snapshotTimer = nullptr;
            bool snapshotPending = false;
            bool stopping = false;

            LayoutDiagnostics() {
                wchar_t directory[MAX_PATH + 1]{};
                auto length = GetTempPathW(MAX_PATH + 1, directory);
                if (length && length <= MAX_PATH) {
                    auto path = std::wstring(directory) + L"SwiftOmniUI-layout-"
                        + std::to_wstring(GetCurrentProcessId()) + L".log";
                    if (_wfopen_s(&file, path.c_str(), L"wb") == 0 && file) {
                        auto utf8 = winrt::to_string(path);
                        std::fprintf(stderr, "[SOUI layout] log: %s\n", utf8.c_str());
                    }
                }
                std::fprintf(stderr, "[SOUI layout] diagnostics active; retaining startup, state history and recent events, pid=%lu\n",
                             static_cast<unsigned long>(GetCurrentProcessId()));
                std::fflush(stderr);
                if (file) {
                    std::fprintf(file, "SOUI layout diagnostics v12 pid=%lu; sizes in DIPs; no input text\n",
                                 static_cast<unsigned long>(GetCurrentProcessId()));
                    std::fflush(file);
                    snapshotTimer = CreateThreadpoolTimer([](PTP_CALLBACK_INSTANCE, void *context, PTP_TIMER) {
                        try {
                            auto &state = *static_cast<LayoutDiagnostics *>(context);
                            std::lock_guard guard(state.lock);
                            state.snapshotPending = false;
                            if (!state.stopping && state.sequence != state.savedSequence) state.saveTail("idle", true);
                        } catch (...) {} // Diagnostics must not terminate a thread-pool callback.
                    }, this, nullptr);
                }
            }

            ~LayoutDiagnostics() {
                { std::lock_guard guard(lock); stopping = true; }
                if (snapshotTimer) {
                    SetThreadpoolTimer(snapshotTimer, nullptr, 0, 0);
                    WaitForThreadpoolTimerCallbacks(snapshotTimer, TRUE);
                    CloseThreadpoolTimer(snapshotTimer);
                }
                if (file) {
                    std::lock_guard guard(lock);
                    saveTail("shutdown", true);
                    std::fclose(file);
                    file = nullptr;
                }
            }

            // Caller holds the lock. Replacing this section bounds disk usage;
            // no geometry, XAML calls, or layout requests occur during a write.
            void saveTail(char const *reason, bool force = false) {
                if (!file || (!force && (sequence == savedSequence || GetTickCount64() - savedAt < 1000))) return;
                if (tailOffset < 0) {
                    if (sequence <= capacity * 2 && !force) return;
                    tailOffset = _ftelli64(file);
                }
                if (_fseeki64(file, tailOffset, SEEK_SET) != 0) return;
                std::fprintf(file, "\n--- state history; snapshot=%s; event=%llu ---\n", reason,
                             static_cast<unsigned long long>(sequence));
                for (auto const &state : states) std::fprintf(file, "%s\n", state.c_str());
                std::fprintf(file, "--- pane, editor and picker presentation history ---\n");
                for (auto const &state : presentations) std::fprintf(file, "%s\n", state.c_str());
                std::fprintf(file, "--- submitted allocation divergences ---\n");
                for (auto const &state : allocations) std::fprintf(file, "%s\n", state.c_str());
                auto count = static_cast<size_t>(std::min<uint64_t>(sequence, capacity));
                auto begin = sequence < capacity ? size_t{0} : next;
                std::fprintf(file, "--- recent %zu events ---\n", count);
                for (size_t index = 0; index < count; ++index)
                    std::fprintf(file, "%s\n", recent[(begin + index) % capacity].c_str());
                auto end = _ftelli64(file);
                std::fflush(file);
                if (end >= 0) _chsize_s(_fileno(file), static_cast<uint64_t>(end));
                savedAt = GetTickCount64();
                savedSequence = sequence;
            }

            void scheduleSnapshot() {
                if (!snapshotTimer || snapshotPending || stopping) return;
                snapshotPending = true;
                LARGE_INTEGER interval;
                interval.QuadPart = -10'000'000LL; // One second, relative, in 100ns units.
                FILETIME due{interval.LowPart, static_cast<DWORD>(interval.HighPart)};
                SetThreadpoolTimer(snapshotTimer, &due, 0, 0);
            }

            void record(char const *message) {
                std::lock_guard guard(lock);
                if (stopping) return;
                char prefix[128]{};
                std::snprintf(prefix, sizeof(prefix), "#%llu +%llums tid=%lu ",
                              static_cast<unsigned long long>(++sequence),
                              static_cast<unsigned long long>(GetTickCount64() - started),
                              static_cast<unsigned long>(GetCurrentThreadId()));
                recent[next] = std::string(prefix) + (message ? message : "");
                auto const &line = recent[next];
                std::string_view event = message ? message : "";
                if (event.substr(0, 20) == "allocation.diverged ") {
                    if (allocations.size() == 128) allocations.pop_front();
                    allocations.push_back(line);
                }
                if (event.substr(0, 6) == "split." || event.substr(0, 7) == "editor."
                    || event.substr(0, 7) == "picker." || event.substr(0, 8) == "runtime.") {
                    if (presentations.size() == 512) presentations.pop_front();
                    presentations.push_back(line);
                }
                if (event.substr(0, 6) == "split." || event.substr(0, 9) == "viewport."
                    || event.substr(0, 12) == "lazy.window " || event.substr(0, 8) == "runtime.") {
                    if (states.size() == 256) states.pop_front();
                    states.push_back(line);
                }
                if (file && sequence <= capacity * 2) {
                    std::fprintf(file, "%s\n", line.c_str());
                    if (sequence == capacity * 2) {
                        std::fprintf(file, "--- startup prefix limit; state history and recent events follow ---\n");
                        tailOffset = _ftelli64(file);
                    }
                    // Per-event fflush made diagnostics part of startup stalls.
                    // Failure dumps still synchronously flush the entire tail.
                    if (sequence % 64 == 0 || GetTickCount64() - prefixFlushedAt >= 100) {
                        std::fflush(file);
                        prefixFlushedAt = GetTickCount64();
                    }
                }
                next = (next + 1) % capacity;
                if (sequence > capacity * 2) {
                    saveTail("running");
                    scheduleSnapshot();
                }
            }

            void failure(int32_t code, char const *message) {
                std::lock_guard guard(lock);
                if (stopping) return;
                std::fprintf(stderr, "[SOUI layout] unhandled XAML exception HRESULT=0x%08x: %s\n",
                             static_cast<unsigned>(code), message ? message : "");
                auto count = static_cast<size_t>(std::min<uint64_t>(sequence, capacity));
                auto begin = sequence < capacity ? size_t{0} : next;
                char reason[1024]{};
                std::snprintf(reason, sizeof(reason), "unhandled XAML exception HRESULT=0x%08x: %s",
                              static_cast<unsigned>(code), message ? message : "");
                saveTail(reason, true);
                std::fprintf(stderr, "[SOUI layout] last %zu events follow; the file contains the full retained tail\n",
                             std::min(count, size_t{256}));
                for (size_t index = 0; index < count; ++index) {
                    auto const &line = recent[(begin + index) % capacity];
                    if (count - index <= 256) std::fprintf(stderr, "%s\n", line.c_str());
                }
                if (file) std::fflush(file);
                std::fflush(stderr);
            }
        };

        LayoutDiagnostics &layoutDiagnostics() {
            static LayoutDiagnostics diagnostics;
            return diagnostics;
        }
    }

    void traceLayout(char const *message) noexcept {
        try { layoutDiagnostics().record(message); }
        catch (...) {} // Diagnostics must not introduce another XAML exception.
    }

    void traceLayoutFailure(int32_t code, char const *message) noexcept {
        try { layoutDiagnostics().failure(code, message); }
        catch (...) {}
    }
}

extern "C" void swiftomniui_winui_layout_trace(char const *message) {
    swiftomniui::traceLayout(message);
}
