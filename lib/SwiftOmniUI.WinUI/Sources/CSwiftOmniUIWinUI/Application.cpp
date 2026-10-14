// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// WinUI started on the calling thread - its own loop, or embedded in a thread
// with none - the doorbell's post onto the UI thread's queue, and the frames.
// Design: docs/design/platforms/winui/runtime.md#starting

#include "Relay.h"

// A debug tree update needs the same 8 MiB stack budget as the other desktop
// hosts. Keep this on the startup object so every consuming EXE receives it.
#pragma comment(linker, "/STACK:8388608")

#include <chrono>
#include <deque>
#include <exception>
#include <io.h>
#include <memory>
#include <mutex>
#include <objbase.h>

#include <winrt/Windows.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Settings.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Windows.Storage.h>
#include "SwiftOmniUIWinUIVersion.h"

namespace swiftomniui {
    SwiftOmniUIWinUICallbacks callbacks{};

    namespace {
        winrt::Microsoft::UI::Dispatching::DispatcherQueue queue{nullptr};
        winrt::event_token rendering{};
        bool holding = false;
        bool ownsMessageLoop = false;

        namespace lifecycle = winrt::Microsoft::Windows::AppLifecycle;
        namespace activation = winrt::Windows::ApplicationModel::Activation;

        lifecycle::AppInstance instance{nullptr};
        winrt::event_token activationListener{};
        std::mutex activationLock;
        std::deque<winrt::agile_ref<lifecycle::AppActivationArguments>> pendingActivations;
        bool activationReady = false;
        bool shuttingDown = false;
        bool windowsAlive = false;
        bool exitQueued = false;
        bool registeredPrimary = false;

        winrt::Microsoft::UI::Dispatching::DispatcherQueue dispatcherQueue() {
            std::lock_guard lock(activationLock);
            return queue;
        }

        /// A storage item's path as the `file:` URL `onOpenURL` hands on - forward slashes past `file:///`.
        std::string fileURL(winrt::hstring const &path) {
            std::wstring text{path.begin(), path.end()};
            for (auto &each : text) if (each == L'\\') each = L'/';
            return "file:///" + winrt::to_string(text);
        }

        /// Reports each URL an activation carries - the files it names, the link it followed.
        void reportActivation(lifecycle::AppActivationArguments const &args) {
            try {
                if (args.Kind() == lifecycle::ExtendedActivationKind::Launch) {
                    if (callbacks.activated) callbacks.activated();
                } else if (args.Kind() == lifecycle::ExtendedActivationKind::File && callbacks.urlOpened) {
                    if (auto files = args.Data().try_as<activation::IFileActivatedEventArgs>()) {
                        for (auto const &item : files.Files()) {
                            if (auto storage = item.try_as<winrt::Windows::Storage::IStorageItem>()) {
                                auto text = fileURL(storage.Path());
                                callbacks.urlOpened(text.c_str());
                            }
                        }
                    }
                } else if (args.Kind() == lifecycle::ExtendedActivationKind::Protocol && callbacks.urlOpened) {
                    if (auto link = args.Data().try_as<activation::IProtocolActivatedEventArgs>()) {
                        callbacks.urlOpened(winrt::to_string(link.Uri().RawUri().c_str()).c_str());
                    }
                }
            } catch (...) {
                report("reporting an activation");
            }
        }

        /// Activation can arrive on an AppLifecycle worker before XAML or the Swift application is ready.
        /// Drain its agile arguments only on the dispatcher, after the primary application's first render.
        void drainActivations() {
            std::deque<winrt::agile_ref<lifecycle::AppActivationArguments>> waiting;
            {
                std::lock_guard lock(activationLock);
                if (!activationReady || shuttingDown) return;
                waiting.swap(pendingActivations);
            }
            for (auto const &args : waiting) reportActivation(args.get());
            swiftomniui_winui_keep_scene_alive(windowsAlive);
        }

        void receiveActivation(lifecycle::AppActivationArguments const &args) {
            winrt::Microsoft::UI::Dispatching::DispatcherQueue dispatcher{nullptr};
            {
                std::lock_guard lock(activationLock);
                if (shuttingDown) return;
                pendingActivations.emplace_back(args);
                if (activationReady) dispatcher = queue;
            }
            if (dispatcher) dispatcher.TryEnqueue(guarded("handling application activation", [] { drainActivations(); }));
        }

        struct RedirectionWait {
            winrt::handle complete{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
            std::mutex lock;
            std::exception_ptr failure;
        };

        /// AppLifecycle redirects asynchronously. Dispatch COM messages while waiting, and also observe the
        /// destination process: it may exit after we found its key but before it acknowledges the request.
        bool redirectActivation(lifecycle::AppInstance const &target, lifecycle::AppActivationArguments const &args) {
            winrt::handle process{OpenProcess(SYNCHRONIZE, FALSE, target.ProcessId())};
            if (!process) {
                if (GetLastError() == ERROR_INVALID_PARAMETER) return false;
                winrt::throw_last_error();
            }
            if (WaitForSingleObject(process.get(), 0) == WAIT_OBJECT_0) return false;
            auto waiting = std::make_shared<RedirectionWait>();
            if (!waiting->complete) winrt::throw_last_error();
            auto sent = target.RedirectActivationToAsync(args);
            sent.Completed([waiting](winrt::Windows::Foundation::IAsyncAction const &action,
                                     winrt::Windows::Foundation::AsyncStatus) {
                try { action.GetResults(); }
                catch (...) {
                    std::lock_guard lock(waiting->lock);
                    waiting->failure = std::current_exception();
                }
                SetEvent(waiting->complete.get());
            });
            HANDLE events[]{waiting->complete.get(), process.get()};
            DWORD index = 0;
            auto result = CoWaitForMultipleHandles(COWAIT_DISPATCH_CALLS | COWAIT_DISPATCH_WINDOW_MESSAGES,
                                                   INFINITE, 2, events, &index);
            winrt::check_hresult(result);
            if (index == 1) {
                sent.Cancel();
                return false;
            }
            std::lock_guard lock(waiting->lock);
            if (waiting->failure) std::rethrow_exception(waiting->failure);
            return true;
        }

        winrt::hstring instanceKey(char const *applicationID) {
            if (applicationID && *applicationID) return winrt::to_hstring(applicationID);
            std::wstring path(256, L'\0');
            for (;;) {
                auto length = GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
                if (!length) winrt::throw_last_error();
                if (length < path.size()) { path.resize(length); return winrt::hstring(path); }
                path.resize(path.size() * 2);
            }
        }

        /// Only the key's owner initializes XAML and the Swift application. Recheck after forwarding so an
        /// instance that unregistered while closing its last window does not swallow the new launch.
        bool selectPrimary(winrt::hstring const &key, lifecycle::AppActivationArguments const &args) {
            for (int attempt = 0; attempt < 3; ++attempt) {
                auto target = lifecycle::AppInstance::FindOrRegisterForKey(key);
                if (!target) continue; // The key can disappear between the SDK's registration and lookup.
                if (target.IsCurrent()) return true;
                AllowSetForegroundWindow(target.ProcessId());
                try {
                    if (!redirectActivation(target, args)) continue;
                } catch (...) {
                    auto replacement = lifecycle::AppInstance::FindOrRegisterForKey(key);
                    if (!replacement) continue;
                    if (replacement.IsCurrent()) return true;
                    if (replacement.ProcessId() == target.ProcessId()) throw;
                    continue;
                }
                auto current = lifecycle::AppInstance::FindOrRegisterForKey(key);
                if (!current) continue;
                if (current.IsCurrent()) return true;
                if (current.ProcessId() == target.ProcessId()) return false;
            }
            winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_RETRY));
        }

        void releaseInstance() {
            {
                std::lock_guard lock(activationLock);
                shuttingDown = true;
                activationReady = false;
                pendingActivations.clear();
                queue = nullptr;
            }
            if (instance) {
                if (registeredPrimary) {
                    instance.UnregisterKey();
                    registeredPrimary = false;
                }
                if (activationListener.value) instance.Activated(activationListener);
                activationListener = {};
                instance = nullptr;
            }
        }

        /// The application: WinUI's control resources and their type information, with no XAML file.
        /// Design: docs/design/platforms/winui/runtime.md#an-application-with-no-xaml
        struct SwiftOmniUIApplication : xaml::ApplicationT<SwiftOmniUIApplication, xaml::Markup::IXamlMetadataProvider> {
            explicit SwiftOmniUIApplication(bool embedded) : embedded(embedded) {
                UnhandledException([](IInspectable const &, xaml::UnhandledExceptionEventArgs const &args) {
                    auto message = winrt::to_string(args.Message());
                    std::fprintf(stderr, "SwiftOmniUI: unhandled XAML exception HRESULT=0x%08lx: %s\n",
                        static_cast<unsigned long>(static_cast<int32_t>(args.Exception())), message.c_str());
                    std::fflush(stderr);
                    // Preserve XAML's original termination behaviour. This is
                    // diagnostics, not recovery from an unknown layout failure.
                });
            }

            void OnLaunched(xaml::LaunchActivatedEventArgs const &) {
                if (embedded) return;
                ownsMessageLoop = true;
                Resources().MergedDictionaries().Append(controls::XamlControlsResources());
                {
                    std::lock_guard lock(activationLock);
                    queue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();
                }
                // The first render may temporarily have no windows. Shutdown becomes eligible only after launch.
                DispatcherShutdownMode(xaml::DispatcherShutdownMode::OnExplicitShutdown);
                callbacks.launched();
                {
                    std::lock_guard lock(activationLock);
                    activationReady = true;
                }
                drainActivations();
            }

            xaml::Markup::IXamlType GetXamlType(winrt::Windows::UI::Xaml::Interop::TypeName const &type) {
                return provider().GetXamlType(type);
            }

            xaml::Markup::IXamlType GetXamlType(winrt::hstring const &name) {
                return provider().GetXamlType(name);
            }

            winrt::com_array<xaml::Markup::XmlnsDefinition> GetXmlnsDefinitions() {
                return provider().GetXmlnsDefinitions();
            }

            /// Made on the first question, as the XAML compiler's own provider is.
            xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider provider() {
                if (!types) types = xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider();
                return types;
            }

            bool embedded;
            xaml::XamlTypeInfo::XamlControlsXamlMetaDataProvider types{nullptr};
        };

        /// Loads the Windows App SDK's runtime the application carries, which registers its classes.
        void loadRuntime() {
            auto runtime = LoadLibraryExW(L"Microsoft.WindowsAppRuntime.dll", nullptr, 0);
            if (!runtime) winrt::throw_last_error();
            using EnsureIsLoaded = HRESULT(__stdcall *)();
            auto ensure = reinterpret_cast<EnsureIsLoaded>(GetProcAddress(runtime, "WindowsAppRuntime_EnsureIsLoaded"));
            if (ensure) winrt::check_hresult(ensure());
        }

        /// SwiftPM does not run the SDK's MSBuild compatibility initializer.
        /// Select the pinned servicing behavior before AppLifecycle or XAML can
        /// lock it. The component package versions are intentionally different.
        void configureRuntimeCompatibility() {
            static std::once_flag configured;
            std::call_once(configured, [] {
                namespace runtime = winrt::Microsoft::Windows::ApplicationModel::WindowsAppRuntime;
                runtime::RuntimeCompatibilityOptions options;
                options.PatchLevel1({SWIFTOMNIUI_WINDOWS_APP_SDK_MAJOR, SWIFTOMNIUI_WINDOWS_APP_SDK_MINOR,
                                     SWIFTOMNIUI_WINDOWS_APP_SDK_PATCH});
                options.Apply();
            });
        }

        /// These stable 2.x optimizations are opt-in, and process-wide. Both
        /// startup paths configure them before constructing any XAML objects;
        /// Application.Start/WindowsXamlManager then lock the selections.
        void configureXaml() {
            static std::once_flag configured;
            std::call_once(configured, [] {
                namespace settings = winrt::Microsoft::UI::Xaml::Settings;
                for (auto change : {settings::XamlChangeId::DefaultStyleOptimizations,
                                    settings::XamlChangeId::IconNoGridOptimization,
                                    settings::XamlChangeId::OptimizeApplyStyles,
                                    settings::XamlChangeId::DeferContextFlyoutInit}) {
                    if (!settings::XamlOptionalChanges::EnableChange(change))
                        winrt::throw_hresult(E_NOTIMPL, L"The deployed WinUI runtime does not support the pinned XAML optimizations.");
                }
            });
        }

        /// Whether the process was given no handle for the stream: a windowed application started with its output
        /// left where it was.
        bool unhanded(DWORD stream) {
            auto handle = GetStdHandle(stream);
            return handle == nullptr || handle == INVALID_HANDLE_VALUE;
        }

        /// A windowed application started from a console writes to that console - a terminal, the editor's task -
        /// where its output was not sent elsewhere; started by itself it has none, and opens none.
        /// Design: docs/design/platforms/winui/runtime.md#a-windowed-application
        void writeToTheStartingConsole() {
            bool out = unhanded(STD_OUTPUT_HANDLE), err = unhanded(STD_ERROR_HANDLE);
            if (!(out || err) || !AttachConsole(ATTACH_PARENT_PROCESS)) return;

            FILE *reopened = nullptr;
            if (out && freopen_s(&reopened, "CONOUT$", "w", stdout) == 0) _dup2(_fileno(stdout), 1);
            if (err && freopen_s(&reopened, "CONOUT$", "w", stderr) == 0) _dup2(_fileno(stderr), 2);
        }
    }
}

namespace swiftomniui {
    void post(void (*work)()) {
        try {
            if (auto dispatcher = dispatcherQueue()) {
                dispatcher.TryEnqueue(guarded("handling TryEnqueue", [work] { work(); }));
            }
        } catch (...) {
            report("posting work to the UI thread");
        }
    }

    void runOnUIThread(std::function<void()> work) {
        try {
            if (auto dispatcher = dispatcherQueue()) {
                dispatcher.TryEnqueue(guarded("handling TryEnqueue", [work = std::move(work)] { work(); }));
            }
        } catch (...) {
            report("handing work to the UI thread");
        }
    }
}

using namespace swiftomniui;

extern "C" int32_t swiftomniui_winui_run(SwiftOmniUIWinUICallbacks const *given) {
    return swiftomniui_winui_run_single_instance(given, nullptr);
}

extern "C" int32_t swiftomniui_winui_run_single_instance(
    SwiftOmniUIWinUICallbacks const *given, char const *applicationID
) {
    callbacks = *given;
    writeToTheStartingConsole();
    try {
        loadRuntime();
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        configureRuntimeCompatibility();
        {
            std::lock_guard lock(activationLock);
            shuttingDown = false;
            activationReady = false;
            pendingActivations.clear();
        }
        windowsAlive = false;
        exitQueued = false;
        registeredPrimary = false;
        instance = lifecycle::AppInstance::GetCurrent();
        auto args = instance.GetActivatedEventArgs();
        // Subscribe before publishing the key: another launch can redirect as soon as registration succeeds.
        activationListener = instance.Activated(guarded("receiving application activation",
            [](IInspectable const &, lifecycle::AppActivationArguments const &args) { receiveActivation(args); }));
        if (!selectPrimary(instanceKey(applicationID), args)) {
            releaseInstance();
            return 0;
        }
        registeredPrimary = true;
        receiveActivation(args);
        configureXaml();
        xaml::Application::Start([](auto &&) { winrt::make<SwiftOmniUIApplication>(false); });
        releaseInstance();
        ownsMessageLoop = false;
        return 0;
    } catch (...) {
        auto failure = report("starting WinUI");
        try { releaseInstance(); } catch (...) { report("releasing the application instance"); }
        ownsMessageLoop = false;
        return failure;
    }
}

extern "C" int32_t swiftomniui_winui_embed(SwiftOmniUIWinUICallbacks const *given) {
    callbacks = *given;
    try {
        static bool embedded = false;
        if (embedded) return 0;
        loadRuntime();
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        configureRuntimeCompatibility();
        configureXaml();
        // The thread's WinUI itself: destroyed as the process exits, in the reverse of the order it stood up in,
        // which is WinUI's own shutdown - kept past it, the process ends in an access violation.
        static auto controller = winrt::Microsoft::UI::Dispatching::DispatcherQueueController::CreateOnCurrentThread();
        // The application first: InitializeForCurrentThread takes its type information, and calls its OnLaunched.
        static auto application = winrt::make<SwiftOmniUIApplication>(true);
        static auto manager = xaml::Hosting::WindowsXamlManager::InitializeForCurrentThread();
        application.Resources().MergedDictionaries().Append(controls::XamlControlsResources());
        {
            std::lock_guard lock(activationLock);
            queue = controller.DispatcherQueue();
        }
        embedded = true;
        return 0;
    } catch (...) {
        return report("embedding WinUI");
    }
}

extern "C" void swiftomniui_winui_pump(double seconds) {
    try {
        auto until = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
        MSG message;
        do {
            while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            MsgWaitForMultipleObjects(0, nullptr, FALSE, 5, QS_ALLINPUT);
        } while (std::chrono::steady_clock::now() < until);
    } catch (...) {
        report("running the thread's messages");
    }
}

extern "C" void swiftomniui_winui_post_turn(void) {
    try {
        if (auto dispatcher = dispatcherQueue()) {
            dispatcher.TryEnqueue(guarded("handling TryEnqueue", [] { callbacks.turn(); }));
        }
    } catch (...) {
        report("posting a turn");
    }
}

extern "C" void swiftomniui_winui_keep_scene_alive(bool alive) {
    if (!ownsMessageLoop) return;
    try {
        windowsAlive = alive;
        auto application = xaml::Application::Current();
        application.DispatcherShutdownMode(xaml::DispatcherShutdownMode::OnExplicitShutdown);
        {
            std::lock_guard lock(activationLock);
            if (alive || !activationReady || shuttingDown || exitQueued) return;
        }
        exitQueued = true;
        auto dispatcher = dispatcherQueue();
        auto accepted = dispatcher && dispatcher.TryEnqueue(winrt::Microsoft::UI::Dispatching::DispatcherQueuePriority::Low,
            guarded("ending the application after its last window", [] {
                exitQueued = false;
                {
                    std::lock_guard lock(activationLock);
                    if (windowsAlive || !pendingActivations.empty() || shuttingDown) return;
                    // An activation rejected as shutting down must observe the key already released.
                    // Otherwise its sender could still find this process and lose the new launch.
                    if (instance && registeredPrimary) {
                        try {
                            instance.UnregisterKey();
                            registeredPrimary = false;
                        } catch (...) {
                            // Still exit when releasing the key fails; process termination also releases it.
                            report("releasing the application instance key");
                        }
                    }
                    shuttingDown = true;
                }
                xaml::Application::Current().Exit();
            }));
        if (!accepted) exitQueued = false;
    } catch (...) {
        report("updating the application's window lifetime");
    }
}

extern "C" void swiftomniui_winui_hold_frames(bool hold) {
    if (hold == holding) return;
    try {
        if (hold) {
            rendering = xaml::Media::CompositionTarget::Rendering(
                [](winrt::Windows::Foundation::IInspectable const &, winrt::Windows::Foundation::IInspectable const &) { callbacks.frame(); });
        } else {
            xaml::Media::CompositionTarget::Rendering(rendering);
        }
        // Held only once WinUI took it: a subscription that failed is asked for again at the next hold.
        holding = hold;
    } catch (...) {
        report("holding the frames");
    }
}

extern "C" bool swiftomniui_winui_holds_frames(void) {
    try {
        return holding;
    } catch (...) {
        report("reading whether frames are held");
        return false;
    }
}

extern "C" SwiftOmniUIObjectRef swiftomniui_winui_retain(SwiftOmniUIObjectRef object) {
    try {
        if (object) reinterpret_cast<::IUnknown *>(object)->AddRef();
        return object;
    } catch (...) {
        report("holding an object");
        return nullptr;
    }
}

extern "C" void swiftomniui_winui_release(SwiftOmniUIObjectRef object) {
    try {
        if (object) reinterpret_cast<::IUnknown *>(object)->Release();
    } catch (...) {
        report("letting go of an object");
    }
}
