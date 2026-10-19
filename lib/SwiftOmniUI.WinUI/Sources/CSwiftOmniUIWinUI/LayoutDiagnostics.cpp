// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

#include "Relay.h"

#include <algorithm>
#include <array>
#include <mutex>

namespace swiftomniui {
    namespace {
        // Temporary startup diagnostics. Retain the beginning and a bounded
        // tail, rather than letting a layout cycle fill the user's disk.
        struct LayoutDiagnostics {
            static constexpr size_t capacity = 4096;
            std::mutex lock;
            std::array<std::string, capacity> recent;
            size_t next = 0;
            uint64_t sequence = 0;
            ULONGLONG started = GetTickCount64();
            FILE *file = nullptr;

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
                std::fprintf(stderr, "[SOUI layout] diagnostics active; retaining first 8192 and last 4096 events, pid=%lu\n",
                             static_cast<unsigned long>(GetCurrentProcessId()));
                std::fflush(stderr);
                if (file) {
                    std::fprintf(file, "SOUI layout diagnostics v1 pid=%lu; sizes in DIPs; no input text\n",
                                 static_cast<unsigned long>(GetCurrentProcessId()));
                    std::fflush(file);
                }
            }

            ~LayoutDiagnostics() { if (file) std::fclose(file); }

            void record(char const *message) {
                std::lock_guard guard(lock);
                char prefix[128]{};
                std::snprintf(prefix, sizeof(prefix), "#%llu +%llums tid=%lu ",
                              static_cast<unsigned long long>(++sequence),
                              static_cast<unsigned long long>(GetTickCount64() - started),
                              static_cast<unsigned long>(GetCurrentThreadId()));
                recent[next] = std::string(prefix) + (message ? message : "");
                // Every written event is flushed before XAML continues, so an
                // LLDB-DAP failure cannot discard the startup prefix as well.
                if (file && sequence <= capacity * 2) {
                    std::fprintf(file, "%s\n", recent[next].c_str());
                    if (sequence == capacity * 2)
                        std::fprintf(file, "--- startup prefix limit; recent events retained for exception dump ---\n");
                    std::fflush(file);
                }
                next = (next + 1) % capacity;
            }

            void failure(int32_t code, char const *message) {
                std::lock_guard guard(lock);
                std::fprintf(stderr, "[SOUI layout] unhandled XAML exception HRESULT=0x%08x: %s\n",
                             static_cast<unsigned>(code), message ? message : "");
                auto count = static_cast<size_t>(std::min<uint64_t>(sequence, capacity));
                auto begin = sequence < capacity ? size_t{0} : next;
                if (file) {
                    std::fprintf(file, "\n--- unhandled XAML exception HRESULT=0x%08x: %s; last %zu of %llu events ---\n",
                                 static_cast<unsigned>(code), message ? message : "", count,
                                 static_cast<unsigned long long>(sequence));
                }
                std::fprintf(stderr, "[SOUI layout] last %zu events follow; the file contains the full retained tail\n",
                             std::min(count, size_t{256}));
                for (size_t index = 0; index < count; ++index) {
                    auto const &line = recent[(begin + index) % capacity];
                    if (file) std::fprintf(file, "%s\n", line.c_str());
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
