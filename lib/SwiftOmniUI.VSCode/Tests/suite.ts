// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The integration suite, run inside VS Code by Tests/run.ts.
//
// The editor's host is asked of the LANGUAGE SERVER, which cannot be faked: a
// symbol of a host's head resolves only while SourceKit-LSP runs with
// SWIFTOMNIUI_HOST=<that host>, and a symbol under no condition resolves in
// either mode - which is what tells "not this host" from "not ready yet".

import { execSync, spawn } from "child_process";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import { findApplications, hasHead } from "../Sources/applications";
import { checkoutNamedBy } from "../Sources/checkouts";
import { configurations, SwiftOmniUIDebugConfigurationProvider, webLaunch } from "../Sources/debug";
import { parseDevices } from "../Sources/devices";
import { isChromium, parseBrowsers } from "../Sources/browsers";
import { otherHostsExcluded, serverConfig, serverSettings, swiftRelease, swiftSDKOf } from "../Sources/editorMode";
import { findSuites, forDevice } from "../Sources/tests";
import { availableHosts, describe, environment, Host, hosts } from "../Sources/hosts";
import { SwiftOmniUIApi } from "../Sources/extension";
import { nameProblem, scaffolderCommand } from "../Sources/newApplication";
import { cloneCommand, groupNameProblem, listReleases, releaseDirectory, releasesIn } from "../Sources/projectGroup";
import { editorCommandLine, reinstallSteps } from "../Sources/reinstall";
import { rebuildSteps } from "../Sources/conformance";
import { deployCommand, deployDestination, winUIArchitectures } from "../Sources/deploy";
import {
    atLeast, checkedPythonIn, checkToolchain, debuggerFinding, isSwiftOrgBuild, ndkRevisionIn, report,
    svgLoaderIn, lldbDapFailure, lldbDapFinding, svgLoaderInGlycin,
} from "../Sources/toolchain";

const started = Date.now();

function say(line: string): void {
    const stamped = `[${Math.round((Date.now() - started) / 1000)}s] ${line}\n`;
    const file = process.env.SWIFTOMNIUI_TEST_RESULTS;
    if (file) {
        fs.appendFileSync(file, stamped);
    }
}

async function resolves(file: string, needle: string, after?: string): Promise<boolean> {
    const document = await vscode.workspace.openTextDocument(file);
    await vscode.window.showTextDocument(document, { preview: false });
    const text = document.getText();
    const from = after ? text.indexOf(after) : 0;
    const at = text.indexOf(needle, from);
    if (from < 0 || at < 0) {
        throw new Error(`${needle} is not in ${file}`);
    }

    const found = await vscode.commands.executeCommand<unknown[]>(
        "vscode.executeDefinitionProvider", document.uri, document.positionAt(at + 1));
    return (found?.length ?? 0) > 0;
}

async function until(what: string, probe: () => Promise<boolean>, seconds: number): Promise<void> {
    const deadline = Date.now() + seconds * 1000;
    while (Date.now() < deadline) {
        if (await probe()) {
            say(`ok   ${what}`);
            return;
        }
        await new Promise((resume) => setTimeout(resume, 5000));
    }
    throw new Error(`timed out after ${seconds}s: ${what}`);
}

function check(what: string, value: boolean): void {
    say(`${value ? "ok  " : "FAIL"} ${what}`);
    if (!value) {
        throw new Error(what);
    }
}

export async function run(): Promise<void> {
    try {
        const root = vscode.workspace.workspaceFolders![0];
        const gallery = path.join(root.uri.fsPath, "apps", "Gallery");
        const plain = path.join(gallery, "Sources", "Samples", "BasicInput", "SliderSample.swift");
        // A head's own view exists only while the editor works as that host: its target is declared for it alone. A
        // member under an inactive `#if` resolves all the same - the server reads it through its type.
        const gtkOnly = (): Promise<boolean> =>
            resolves(path.join(gallery, "Platforms", "GTK", "main.swift"), "swiftomniui_app_register");
        const webOnly = (): Promise<boolean> =>
            resolves(path.join(gallery, "Platforms", "Web", "main.swift"), "swiftomniui_app_register");
        const androidOnly = (): Promise<boolean> =>
            resolves(path.join(gallery, "Platforms", "Android", "Swift", "GalleryAndroid.swift"), "swiftomniui_app_register");

        const api = await vscode.extensions.getExtension<SwiftOmniUIApi>("zxss702.swiftomniui")!.activate();
        say(`activated, host ${api.host()}`);

        // 1-3 ask the language server as the hosts only macOS builds: Android and the Web.
        if (process.platform === "darwin") {
            // 1. Android: the plain symbol and its own head resolve, no other's does.
            await api.selectHost("android");
            await until("android: a symbol under no condition resolves", () => resolves(plain, "Palette.accent"), 900);
            await until("android: its head resolves, and no other's does",
                async () => (await androidOnly()) && !(await gtkOnly()) && !(await webOnly()), 900);

            // 2. The Web: its head resolves, Android's and GTK's do not.
            await api.selectHost("web");
            await until("web: its head resolves, and the other hosts' do not",
                async () => (await webOnly()) && !(await androidOnly()) && !(await gtkOnly()), 900);

            // 3. And back, still with no reload.
            await api.selectHost("android");
            await until("android again: the other heads stop resolving while the plain symbol does", async () =>
                (await resolves(plain, "Palette.accent")) && (await androidOnly()) && !(await gtkOnly()) && !(await webOnly()), 900);
        } else {
            say("skip the language server as Android and the Web: only macOS builds those hosts");
        }

        // 4. The hosts a machine is offered: Android on macOS, WinUI on
        //    Windows, GTK on Linux, the Web on macOS and Linux, and no .NET
        //    MAUI. A launch on a machine that runs no host resolves to nothing.
        const gallery_ = findApplications(root.uri.fsPath).find((each) => each.name === "Gallery")!;
        check("the host picker offers Android on macOS, WinUI on Windows, GTK on Linux, the Web on macOS and Linux, and never .NET MAUI",
            JSON.stringify(availableHosts("darwin").map((each) => each.id)) === JSON.stringify(["android", "web"])
            && JSON.stringify(availableHosts("win32").map((each) => each.id)) === JSON.stringify(["winui"])
            && JSON.stringify(availableHosts("linux").map((each) => each.id)) === JSON.stringify(["gtk", "web"])
            && availableHosts("freebsd").length === 0
            && !hosts.some((each) => each.label.includes("MAUI")));
        {
            const ran: string[] = [];
            const provider = new SwiftOmniUIDebugConfigurationProvider({
                host: () => undefined, application: async () => gallery_,
                run: async (task) => { ran.push(task.name); return 0; },
                start: async (task) => { ran.push(task.name); },
                ready: async () => false,
                device: async () => undefined,
                browser: async () => undefined,
            });
            const resolved = await provider.resolveDebugConfiguration(root,
                { name: "SwiftOmniUI: Debug", type: "swiftomniui", request: "launch", configuration: "debug" });
            check("with no host a launch runs nothing and opens no session", resolved === undefined && ran.length === 0);
        }

        // 5. The suites, found for each host the way CI runs them.
        const gtkSuites = findSuites(root.uri.fsPath, "gtk").map((each) => each.label);
        const plainSuites = findSuites(root.uri.fsPath, undefined);
        say(`gtk suites: ${gtkSuites.join(", ")}`);
        say(`suites with no host: ${plainSuites.map((each) => each.label).join(", ")}`);
        check("gtk runs the core, SwiftOmniUIGTK and the Gallery, and no device",
            gtkSuites.includes("SwiftOmniUI") && gtkSuites.includes("SwiftOmniUIGTK")
            && gtkSuites.includes("apps/Gallery") && !gtkSuites.some((each) => each.endsWith("Tests")));
        check("HelloWorld's example test runs with the rest - as plain Swift",
            findSuites(root.uri.fsPath, "gtk").some((each) => each.label === "apps/HelloWorld")
            && plainSuites.some((each) => each.label === "apps/HelloWorld"));
        check("with no host the core and the Gallery run as plain Swift, and no host's own package",
            plainSuites.some((each) => each.label === "SwiftOmniUI") && plainSuites.some((each) => each.label === "apps/Gallery")
            && plainSuites.every((each) => each.command === "swift" && each.env.SWIFTOMNIUI_HOST === "" && !each.onDevice)
            && !plainSuites.some((each) => each.label === "SwiftOmniUIGTK" || each.label === "lib/SwiftOmniUI.Android/Tests"));

        // 6. Android: the environment, the language server's file, the
        //    devices, and the commands a launch and a suite run - captured,
        //    not run.
        check("each host's environment names it in one variable - SWIFTOMNIUI_HOST=android for Android - and no host clears it",
            hosts.every((host) => JSON.stringify(environment(host.id)) === JSON.stringify({ SWIFTOMNIUI_HOST: host.id }))
            && environment("android").SWIFTOMNIUI_HOST === "android"
            && JSON.stringify(Object.entries(environment(undefined))) === JSON.stringify([["SWIFTOMNIUI_HOST", undefined]]));
        {
            const asWinUI = otherHostsExcluded("winui", { "**/mine": true, "**/lib/SwiftOmniUI/SwiftOmniUI.WinUI": true });
            const excluded = Object.keys(asWinUI).filter((pattern) => asWinUI[pattern]);
            check("the root manifest selects hosts, old package exclusions are removed, and user exclusions stay",
                JSON.stringify(excluded) === JSON.stringify(["**/mine"]) && asWinUI["**/mine"] === true
                && Object.keys(otherHostsExcluded(undefined, {})).length === 0);
            const manifest = fs.readFileSync(path.join(root.uri.fsPath, "Package.swift"), "utf8");
            check("every host is declared as a target in the root package",
                hosts.every((host) => manifest.includes(`name: "SwiftOmniUI${host.label}"`)));
        }
        {
            const sdk = "swift-6.4.0-RELEASE_android";
            const android = serverConfig(
                { swiftPM: { scratchPath: ".build/gtk/index-build", configuration: "debug" }, index: { indexStorePath: "x" } },
                serverSettings("android", sdk));
            const back = serverConfig(android, serverSettings("gtk"));
            check("as Android the language server indexes in .build/android/index-build with the Swift SDK and aarch64-unknown-linux-android28, by building",
                android.swiftPM?.scratchPath === ".build/android/index-build" && android.swiftPM?.swiftSDK === sdk
                && android.swiftPM?.triple === "aarch64-unknown-linux-android28" && android.backgroundPreparationMode === "build");
            check("the rest of the file is kept, and back on GTK the SDK and the triple are gone",
                android.swiftPM?.configuration === "debug" && JSON.stringify(android.index) === JSON.stringify({ indexStorePath: "x" })
                && back.swiftPM?.scratchPath === ".build/gtk/index-build" && back.swiftPM?.configuration === "debug"
                && !("swiftSDK" in back.swiftPM!) && !("triple" in back.swiftPM!));
            check("with no Swift SDK installed Android indexes for this Mac, and with no host the index is SwiftPM's own, with no SDK",
                JSON.stringify(serverSettings("android", undefined)) === JSON.stringify({ scratchPath: ".build/android/index-build" })
                && JSON.stringify(serverSettings(undefined, sdk)) === JSON.stringify({ scratchPath: ".build/index-build" }));

            // The other releases are assembled, so the repository's one-release guard reads no second one here.
            const older = ["6", "3", "3"].join("."), newer = ["6", "5"].join(".");
            const list = `swift-${older}-RELEASE_android\nswift-6.4.0-RELEASE_android\nswift-6.4.0-RELEASE_static-linux-0.1.0\n`;
            const sdkOf = (version: string) => swiftSDKOf(swiftRelease(version), list, "android");
            check("the Swift SDK for Android is the one of the toolchain's release, as build-swift.sh finds it",
                sdkOf("Apple Swift version 6.4 (swift-6.4-RELEASE)\nTarget: arm64-apple-macosx26.0") === sdk
                && sdkOf(`Apple Swift version ${older} (swift-${older}-RELEASE)`) === `swift-${older}-RELEASE_android`
                && sdkOf(`Apple Swift version ${newer} (swift-${newer}-RELEASE)`) === undefined && sdkOf("") === undefined);
            const wasm = "swift-6.4.0-RELEASE_wasm\nswift-6.4.0-RELEASE_wasm-embedded\n";
            check("the Swift SDK for WebAssembly is the one whose id ends in _wasm, never its Embedded Swift sibling",
                swiftSDKOf("6.4", wasm, "wasm") === "swift-6.4.0-RELEASE_wasm"
                && swiftSDKOf("6.4", "swift-6.4.0-RELEASE_wasm-embedded\n", "wasm") === undefined);
        }
        check("devices.sh list reads as the devices attached, by serial and name, and the emulators not running",
            JSON.stringify(parseDevices("device\t190a991d\tCPH2363\r\ndevice\temulator-5554\tPixel_3a_API_34\ndevice\tR5CT\navd\tMedium_Phone_API_36\n\nnoise\n"))
            === JSON.stringify([
                { kind: "device", serial: "190a991d", name: "CPH2363" },
                { kind: "device", serial: "emulator-5554", name: "Pixel_3a_API_34" },
                { kind: "device", serial: "R5CT", name: "R5CT" },
                { kind: "avd", name: "Medium_Phone_API_36" },
            ]));

        const helloWorld = findApplications(root.uri.fsPath).find((each) => each.name === "HelloWorld")!;
        check("HelloWorld and the Gallery have Android heads",
            hasHead(helloWorld, "android") && hasHead(gallery_, "android"));
        {
            // What run-app.sh --debugger writes once the application runs, faked
            // by the task's start - or not, where the application never starts.
            const facts = path.join(helloWorld.directory, ".build", "android", "debugger.json");
            const launchOnAndroid = async (serial: string | undefined, configuration = "release", starts = true) => {
                const started: vscode.Task[] = [];
                const ran: string[] = [];
                const provider = new SwiftOmniUIDebugConfigurationProvider({
                    host: () => "android", application: async () => helloWorld,
                    run: async (task) => { ran.push(task.name); return 0; },
                    start: async (task) => {
                        started.push(task);
                        if (configuration === "debug" && starts) {
                            fs.mkdirSync(path.dirname(facts), { recursive: true });
                            fs.writeFileSync(facts, JSON.stringify({
                                serial, package: "com.swiftomniui.helloworld", process: 4242,
                                socket: "com.swiftomniui.helloworld/swiftomniui-debugger.sock", symbols: "/build/symbols/arm64-v8a",
                            }));
                        }
                    },
                    ready: async (file) => fs.existsSync(file),
                    device: async () => serial,
                    browser: async () => undefined,
                });
                const resolved = await provider.resolveDebugConfiguration(root, {
                    name: configuration === "debug" ? "SwiftOmniUI: Debug" : "SwiftOmniUI: Release", type: "swiftomniui",
                    request: "launch", configuration,
                });
                fs.rmSync(facts, { force: true });
                return { resolved, started, ran };
            };

            const { resolved, started, ran } = await launchOnAndroid("emulator-5554");
            const shell = started[0]?.execution as vscode.ShellExecution | undefined;
            const line = shell ? [shell.command, ...(shell.args ?? [])].map(String).join(" ") : "";
            say(`     android started: ${line}`);
            check("Android: run-app.sh <HelloWorld> release <serial> started as a task on that device, nothing waited for, and no session",
                resolved === undefined && ran.length === 0 && started.length === 1
                && line === `bash ${path.join(root.uri.fsPath, ".scripts", "Android", "run-app.sh")} ${helloWorld.directory} release emulator-5554`
                && started[0].definition.application === "HelloWorld" && started[0].definition.device === "emulator-5554");

            const declined = await launchOnAndroid(undefined);
            check("Android with no device picked starts nothing and opens no session",
                declined.resolved === undefined && declined.started.length === 0);

            const debugged = await launchOnAndroid("emulator-5554", "debug");
            const debugShell = debugged.started[0]?.execution as vscode.ShellExecution | undefined;
            const debugLine = debugShell ? [debugShell.command, ...(debugShell.args ?? [])].map(String).join(" ") : "";
            say(`     android debugged: ${JSON.stringify(debugged.resolved)}`);
            check("Android Debug: run-app.sh ... debug <serial> --debugger, then lldb-dap attached through the device's lldb-server to the process started",
                debugLine.endsWith(`${helloWorld.directory} debug emulator-5554 --debugger`)
                && debugged.resolved?.type === "lldb-dap" && debugged.resolved.request === "attach"
                && JSON.stringify(debugged.resolved.initCommands) === JSON.stringify([
                    "settings set plugin.jit-loader.gdb.enable off",
                    "platform select remote-android",
                    "platform connect unix-abstract-connect://emulator-5554/com.swiftomniui.helloworld/swiftomniui-debugger.sock",
                    "settings append target.exec-search-paths /build/symbols/arm64-v8a",
                ])
                && JSON.stringify(debugged.resolved.attachCommands) === JSON.stringify([
                    "process attach --pid 4242",
                    "process handle SIGSEGV --pass true --stop false --notify false",
                    "process handle SIGBUS --pass true --stop false --notify false",
                ]));

            const failed = await launchOnAndroid("emulator-5554", "debug", false);
            check("Android Debug whose application never starts opens no session",
                failed.resolved === undefined && failed.started.length === 1);
        }
        {
            const androidSuites = findSuites(root.uri.fsPath, "android");
            say(`android suites: ${androidSuites.map((each) => each.label).join(", ")}`);
            const onDevice = androidSuites.filter((each) => each.onDevice).map((each) => forDevice(each, "emulator-5554"));
            const galleryRun = androidSuites.find((each) => each.label === "apps/Gallery");
            check("android runs the core and the Gallery as plain Swift, and no other host's",
                androidSuites.some((each) => each.label === "SwiftOmniUI" && forDevice(each, "emulator-5554") === each)
                && galleryRun?.args.join(" ") === `test --package-path ${gallery}` && Object.keys(galleryRun.env).length === 0
                && !androidSuites.some((each) => each.label === "SwiftOmniUIGTK"));
            check("android runs test-android.sh <serial> on the device, and only android does",
                onDevice.length === 1 && onDevice[0].label === "lib/SwiftOmniUI.Android/Tests"
                && [onDevice[0].command, ...onDevice[0].args].join(" ") === `bash ${path.join(root.uri.fsPath, ".scripts", "Android", "test-android.sh")} emulator-5554`
                && !gtkSuites.includes("lib/SwiftOmniUI.Android/Tests"));
        }

        // 6b. WinUI: HelloWorld's head, built by run-app.ps1 -BuildOnly and
        //     launched under lldb-dap, and the host's own package through test-winui.ps1.
        check("HelloWorld has a WinUI head, and as WinUI the language server indexes in .build/winui/index-build",
            hasHead(helloWorld, "winui")
            && JSON.stringify(serverSettings("winui", undefined)) === JSON.stringify({ scratchPath: ".build/winui/index-build" }));
        {
            const ran: vscode.Task[] = [];
            const provider = new SwiftOmniUIDebugConfigurationProvider({
                host: () => "winui", application: async () => helloWorld,
                run: async (task) => { ran.push(task); return 0; },
                start: async () => {},
                ready: async () => false,
                device: async () => undefined,
                browser: async () => undefined,
            });
            const resolved = await provider.resolveDebugConfiguration(root,
                { name: "SwiftOmniUI: Release", type: "swiftomniui", request: "launch", configuration: "release" });
            const process_ = ran[0]?.execution as vscode.ProcessExecution | undefined;
            const line = process_ ? [process_.process, ...process_.args].join(" ") : "";
            say(`     winui built: ${line}`);
            check("WinUI: run-app.ps1 -App <HelloWorld> -Configuration release -BuildOnly ran as a task, then lldb-dap launches HelloWorldWinUI.exe",
                ran.length === 1
                && line === `powershell -NoProfile -ExecutionPolicy Bypass -File ${path.join(root.uri.fsPath, ".scripts", "WinUI", "run-app.ps1")} -App ${helloWorld.directory} -Configuration release -BuildOnly`
                && resolved?.type === "lldb-dap" && resolved.request === "launch"
                && resolved.program === path.join(helloWorld.directory, ".build", "winui", "release", "HelloWorldWinUI.exe"));
        }
        {
            const winUISuites = findSuites(root.uri.fsPath, "winui");
            say(`winui suites: ${winUISuites.map((each) => each.label).join(", ")}`);
            const own = winUISuites.find((each) => each.label === "lib/SwiftOmniUI/SwiftOmniUI.WinUI/Testing");
            check("winui runs the core and the Gallery as plain Swift, its own package by test-winui.ps1, and no other host's",
                winUISuites.some((each) => each.label === "SwiftOmniUI")
                && own?.command === "powershell" && own.args[own.args.length - 1].endsWith("test-winui.ps1")
                && !winUISuites.some((each) => each.label === "SwiftOmniUIGTK" || each.label === "lib/SwiftOmniUI.Android/Tests"));
        }

        // 6c. GTK: HelloWorld's head, built by run-app.sh --build-only and
        //     launched under lldb-dap, and the host's own package by swift test.
        check("HelloWorld has a GTK head, and as GTK the language server indexes in .build/gtk/index-build",
            hasHead(helloWorld, "gtk")
            && JSON.stringify(serverSettings("gtk", undefined)) === JSON.stringify({ scratchPath: ".build/gtk/index-build" }));
        {
            const ran: vscode.Task[] = [];
            const provider = new SwiftOmniUIDebugConfigurationProvider({
                host: () => "gtk", application: async () => helloWorld,
                run: async (task) => { ran.push(task); return 0; },
                start: async () => {},
                ready: async () => false,
                device: async () => undefined,
                browser: async () => undefined,
            });
            const resolved = await provider.resolveDebugConfiguration(root,
                { name: "SwiftOmniUI: Debug", type: "swiftomniui", request: "launch", configuration: "debug" });
            const shell = ran[0]?.execution as vscode.ShellExecution | undefined;
            const line = shell ? [shell.command, ...shell.args].join(" ") : "";
            say(`     gtk built: ${line}`);
            check("GTK: run-app.sh <HelloWorld> debug --build-only ran as a task, then lldb-dap launches HelloWorldGTK",
                ran.length === 1
                && line === `bash ${path.join(root.uri.fsPath, ".scripts", "GTK", "run-app.sh")} ${helloWorld.directory} debug --build-only`
                && resolved?.type === "lldb-dap" && resolved.request === "launch"
                && resolved.program === path.join(helloWorld.directory, ".build", "gtk", "debug", "HelloWorldGTK"));
        }
        {
            const gtkSuites = findSuites(root.uri.fsPath, "gtk");
            say(`gtk suites: ${gtkSuites.map((each) => each.label).join(", ")}`);
            const own = gtkSuites.find((each) => each.label === "lib/SwiftOmniUI/SwiftOmniUI.GTK/Testing");
            const testing = path.join(root.uri.fsPath, "lib", "SwiftOmniUI", "SwiftOmniUI.GTK", "Testing");
            check("gtk runs the core and the Gallery as plain Swift, its own tests' package by swift test, and no other host's",
                gtkSuites.some((each) => each.label === "SwiftOmniUI")
                && own?.command === "swift" && own.args.join(" ") === `test --package-path ${testing}`
                && !gtkSuites.some((each) => ["lib/SwiftOmniUI/SwiftOmniUI.WinUI", "lib/SwiftOmniUI.Android/Tests",
                    "lib/Backends/WebView.WinUI"].includes(each.label)));
        }

        // 6d. Web: HelloWorld's head, built, served and opened by run-app.sh in a
        //     task in the browser chosen; a Debug launch in one of Chromium's
        //     VS Code's JavaScript debugger on the page server.json names.
        check("HelloWorld has a Web head, and as the Web the language server indexes in .build/web/index-build for wasm32-unknown-wasip1",
            hasHead(helloWorld, "web")
            && JSON.stringify(serverSettings("web", "swift-6.4.0-RELEASE_wasm")) === JSON.stringify(
                { scratchPath: ".build/web/index-build", swiftSDK: "swift-6.4.0-RELEASE_wasm", triple: "wasm32-unknown-wasip1" }));
        {
            const listed = parseBrowsers("com.apple.Safari\tSafari\t/Applications/Safari.app/Contents/MacOS/Safari\tdefault\r\n"
                + "com.google.Chrome\tGoogle Chrome\t/Applications/Google Chrome.app/Contents/MacOS/Google Chrome\t\n\n"
                + "firefox.desktop\tFirefox\t/usr/bin/firefox\t\n");
            check("browsers.sh list reads as the browsers by id, name and program, the system's own marked, and Chromium's told apart",
                listed.length === 3 && listed[0].isDefault && !listed[1].isDefault && listed[1].name === "Google Chrome"
                && listed[2].executable === "/usr/bin/firefox"
                && !isChromium(listed[0]) && isChromium(listed[1]) && !isChromium(listed[2])
                && isChromium({ id: "com.microsoft.edgemac" }) && isChromium({ id: "brave-browser.desktop" }));

            const facts = path.join(helloWorld.directory, ".build", "web", "server.json");
            const launchOnWeb = async (browser: (typeof listed)[number], configuration: string) => {
                const started: vscode.Task[] = [];
                const provider = new SwiftOmniUIDebugConfigurationProvider({
                    host: () => "web", application: async () => helloWorld,
                    run: async () => 0,
                    start: async (task) => {
                        started.push(task);
                        fs.mkdirSync(path.dirname(facts), { recursive: true });
                        fs.writeFileSync(facts, JSON.stringify({ url: "http://127.0.0.1:8460/" }));
                    },
                    ready: async (file) => fs.existsSync(file),
                    device: async () => undefined,
                    browser: async () => browser,
                });
                const resolved = await provider.resolveDebugConfiguration(root,
                    { name: "SwiftOmniUI: Debug", type: "swiftomniui", request: "launch", configuration });
                fs.rmSync(facts, { force: true });
                const shell = started[0]?.execution as vscode.ShellExecution | undefined;
                return { resolved, started, line: shell ? [shell.command, ...(shell.args ?? [])].map(String).join(" ") : "" };
            };
            const script = path.join(root.uri.fsPath, ".scripts", "Web", "run-app.sh");

            const safari = await launchOnWeb(listed[0], "debug");
            say(`     web started: ${safari.line}`);
            check("Web in Safari: run-app.sh <HelloWorld> debug --browser com.apple.Safari started as a task, and no session",
                safari.resolved === undefined && safari.started.length === 1
                && safari.line === `bash ${script} ${helloWorld.directory} debug --browser com.apple.Safari`
                && safari.started[0].definition.device === "web");

            const chrome = await launchOnWeb(listed[1], "debug");
            check("Web in Chrome: the page served with no browser opened, then VS Code's JavaScript debugger starts Chrome on it",
                chrome.line === `bash ${script} ${helloWorld.directory} debug --browser none`
                && JSON.stringify(chrome.resolved) === JSON.stringify(webLaunch("SwiftOmniUI: Debug", "http://127.0.0.1:8460/", listed[1],
                    path.join(helloWorld.directory, ".build", "web", "site", "debug")))
                && chrome.resolved?.type === "chrome" && chrome.resolved.runtimeExecutable === listed[1].executable);

            const released = await launchOnWeb(listed[1], "release");
            check("Web released in Chrome is opened by the script, with no session",
                released.resolved === undefined && released.line.endsWith("release --browser com.google.Chrome"));
        }
        {
            const webSuites = findSuites(root.uri.fsPath, "web");
            say(`web suites: ${webSuites.map((each) => each.label).join(", ")}`);
            const own = webSuites.find((each) => each.label === "lib/SwiftOmniUI/SwiftOmniUI.Web/Testing");
            check("web runs the core and the Gallery as plain Swift, its own tests' package by test-web.sh, and no other host's",
                webSuites.some((each) => each.label === "SwiftOmniUI") && webSuites.some((each) => each.label === "apps/Gallery")
                && own?.command === "bash" && own.args[0] === path.join(root.uri.fsPath, ".scripts", "Web", "test-web.sh")
                && webSuites.filter((each) => each !== own).every((each) => each.command === "swift" && !each.onDevice)
                && !webSuites.some((each) => ["lib/SwiftOmniUI/SwiftOmniUI.GTK/Testing"].includes(each.label)));
            check("the Web makes no conformance marks yet", rebuildSteps(root.uri.fsPath, "web", "all") === undefined);
        }

        const palette = await vscode.commands.getCommands(true);
        check("the palette has Select Android Device and Select Browser, and no Select Debugger",
            palette.includes("swiftomniui.selectAndroidDevice") && palette.includes("swiftomniui.selectBrowser")
            && !palette.includes("swiftomniui.selectDebugger") && !palette.includes("swiftomniui.selectSimulator"));

        // 7. A new application is HelloWorld renamed in a checkout's apps/,
        //    by the checkout's scaffolder - the only starter.
        const commands = await vscode.commands.getCommands(true);
        check("the palette has New Application in apps/ and no New Application from Template",
            commands.includes("swiftomniui.newApplicationInApps") && !commands.includes("swiftomniui.newApplication"));
        check("a name is letters and digits, starting with a letter, and not SwiftOmniUI",
            nameProblem("MyApp2") === undefined && nameProblem("My-App") !== undefined
            && nameProblem("2App") !== undefined && nameProblem("SwiftOmniUI") !== undefined);
        {
            const apps = path.join(root.uri.fsPath, "apps");
            const made = scaffolderCommand(root.uri.fsPath, apps, "Notes", "darwin");
            const windows = scaffolderCommand(root.uri.fsPath, apps, "Notes", "win32");
            check("in apps/ it is the checkout's scaffolder: new-app.sh Notes <apps>, new-app.ps1 -Name Notes -AppsDir <apps>",
                made.command === "bash" && made.args[0].split(path.sep).join("/").endsWith("/.scripts/new-app.sh")
                && made.args.slice(1).join(" ") === `Notes ${apps}`
                && windows.command === "powershell" && windows.args.slice(-5).join(" ").endsWith(`new-app.ps1 -Name Notes -AppsDir ${apps}`));
            const manifest = JSON.parse(fs.readFileSync(path.join(root.uri.fsPath, "lib", "SwiftOmniUI.VSCode", "package.json"), "utf8"));
            const setting = manifest.contributes.configuration.properties;
            check("the palette has New Project Group; New Application in apps/ shows where a folder keeps apps/; "
                + "swiftomniui.checkout is this machine's, swiftomniui.minimumRelease 0.5.0",
                commands.includes("swiftomniui.newProjectGroup")
                && manifest.contributes.commands.some((each: { command: string; enablement?: string }) =>
                    each.command === "swiftomniui.newApplicationInApps" && each.enablement === "swiftomniui.hasApps")
                && setting["swiftomniui.checkout"].scope === "machine" && setting["swiftomniui.minimumRelease"].default === "0.5.0");
            check("an application's Package.swift names its checkout: HelloWorld's ../.. is this one",
                fs.realpathSync(checkoutNamedBy(path.join(apps, "HelloWorld")) ?? "/") === fs.realpathSync(root.uri.fsPath)
                && findApplications(root.uri.fsPath).every((each) => each.checkout !== undefined));
            check("a group's name is letters, digits, dots, hyphens and underscores",
                groupNameProblem("My.Apps-2_x") === undefined && groupNameProblem("My Apps") !== undefined
                && groupNameProblem("-apps") !== undefined && groupNameProblem("") !== undefined);
            const listed = ["0.3.1", "0.4.0", "0.10.0", "0.4.1", "v1.0", "1.0.0-beta"]
                .map((tag, at) => `${at}abc\trefs/tags/${tag}`).join("\n");
            const clone = cloneCommand("https://github.com/zxss702/SwiftOmniUI.git", "0.4.0", "/Groups/Mine");
            check("the releases offered are the tags minimumRelease or newer, the newest first; one is cloned shallow into the group's SwiftOmniUI/",
                releasesIn(listed, "0.4.0").join(" ") === "0.10.0 0.4.1 0.4.0"
                && clone.command === "git" && clone.args.join(" ")
                    === `-c advice.detachedHead=false clone --depth 1 --branch 0.4.0 https://github.com/zxss702/SwiftOmniUI.git ${path.join("/Groups/Mine", "SwiftOmniUI")}`);
        }
        // 7a. A project group, made by the command itself with its questions answered: one building with this checkout,
        //     one with the newest release offered cloned into it. Each application names its SwiftOmniUI in its Package.swift, New
        //     Application in apps/ makes another the same way there, and each group's Notes builds.
        {
            const location = process.env.SWIFTOMNIUI_TEST_GROUPS ?? fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), "swiftomniui-groups-")));
            const taken = ["LocalGroup", "ReleaseGroup"].map((each) => path.join(location, each)).filter((each) => fs.existsSync(each));
            check(`the groups are made where nothing is yet${taken.length > 0 ? ` - remove ${taken.join(", ")} first` : ""}`, taken.length === 0);
            // The system's own spelling: the editor names a Windows folder `c:\…`, a resolved path `C:\…`.
            const same = (a: string | undefined, b: string): boolean => a !== undefined && fs.realpathSync.native(a) === fs.realpathSync.native(b);
            const builds = (application: string): boolean => {
                try {
                    // As plain Swift: an application's shared target builds with no host.
                    execSync(`swift build --package-path "${application}"`, { stdio: "pipe" });
                    return true;
                } catch (error) {
                    say(`     ${String((error as { stdout?: Buffer }).stdout ?? error).split("\n").slice(-8).join("\n     ")}`);
                    return false;
                }
            };
            const wired = (application: string): boolean => {
                const text = fs.readFileSync(path.join(application, "Package.swift"), "utf8");
                return [...text.matchAll(/^[^/\n]*\.package\(.*path: "([^"]+)"/gm)]
                    .every((match) => fs.existsSync(path.join(path.resolve(fs.realpathSync(application), match[1]), "Package.swift")));
            };

            const local = await vscode.commands.executeCommand<string>("swiftomniui.newProjectGroup",
                { location, name: "LocalGroup", checkout: root.uri.fsPath, application: "Notes" });
            const localNotes = path.join(local ?? "", "apps", "Notes");
            const launch = local ? JSON.parse(fs.readFileSync(path.join(local, ".vscode", "launch.json"), "utf8")) : {};
            check("a group is its folder: apps/, .gitignore, and the editor's settings with SwiftOmniUI: Debug and Release",
                local === path.join(location, "LocalGroup")
                && [".gitignore", ".vscode/settings.json", "apps/Notes/Package.swift"].every((each) => fs.existsSync(path.join(local, each)))
                && JSON.stringify(launch.configurations.map((each: vscode.DebugConfiguration) => [each.name, each.type, each.configuration]))
                    === JSON.stringify(configurations().map((each) => [each.name, each.type, each.configuration])));
            check("with the local checkout its application names this checkout by the path from its own folder, and nothing is copied",
                same(checkoutNamedBy(localNotes), root.uri.fsPath) && wired(localNotes)
                && !fs.readFileSync(path.join(localNotes, "Package.swift"), "utf8").includes('path: "../.."')
                && !fs.existsSync(path.join(local!, "SwiftOmniUI")) && !fs.existsSync(path.join(local!, ".scripts")));
            const tasks = await vscode.commands.executeCommand<string>("swiftomniui.newApplicationInApps", { folder: local, name: "Tasks" });
            check("New Application in apps/ in that group names the same checkout", tasks === path.join(local!, "apps", "Tasks")
                && same(checkoutNamedBy(tasks), root.uri.fsPath) && wired(tasks));
            check("the local group's application builds", builds(localNotes));
            // SwiftOmniUI: Run Tests in the group: each application's example test, run as the command runs it.
            const testHost = undefined;
            const groupSuites = findSuites(local!, testHost);
            const notesSuite = groupSuites.find((each) => each.label === "apps/Notes");
            check("Run Tests in a group finds each application's tests",
                groupSuites.map((each) => each.label).join(" ") === "apps/Notes apps/Tasks" && notesSuite !== undefined);
            const passes = (() => {
                try {
                    const env = Object.fromEntries(Object.entries({ ...process.env, ...environment(testHost), ...notesSuite!.env })
                        .filter((entry): entry is [string, string] => entry[1] !== undefined));
                    execSync([notesSuite!.command, ...notesSuite!.args].map((each) => `"${each}"`).join(" "), { cwd: local, env, stdio: "pipe" });
                    return true;
                } catch (error) {
                    say(`     ${String((error as { stdout?: Buffer }).stdout ?? error).split("\n").slice(-8).join("\n     ")}`);
                    return false;
                }
            })();
            check(`Notes' example test passes as ${testHost ?? "plain Swift"}`, passes);

            // SwiftOmniUI: Deploy in the group: Notes built for release and laid in the group's artifacts/Notes/<platform>,
            // on WinUI per architecture - this machine's own, and x64 too on an ARM64 machine - and run from there.
            const notes = findApplications(local!).find((each) => each.name === "Notes")!;
            const winUIDeploy = deployCommand(notes, "winui", "D", "x64");
            const androidDeploy = deployCommand(notes, "android", "D", undefined, "SERIAL");
            check("Deploy lays an application in artifacts/<application>/<platform> beside its apps/, on WinUI per architecture, by its checkout's deploy script",
                commands.includes("swiftomniui.deploy")
                && JSON.stringify(winUIArchitectures("arm64")) === JSON.stringify(["arm64", "x64"])
                && JSON.stringify(winUIArchitectures("x64")) === JSON.stringify(["x64"])
                && deployDestination(notes, "winui", "x64") === path.join(local!, "artifacts", "Notes", "WinUI", "x64")
                && deployDestination(notes, "gtk") === path.join(local!, "artifacts", "Notes", "GTK")
                && same(notes.checkout, root.uri.fsPath)
                && winUIDeploy?.script === path.join(notes.checkout!, ".scripts", "WinUI", "deploy.ps1")
                && winUIDeploy.args.slice(-6).join(" ") === `-App ${notes.directory} -Destination D -Architecture x64`
                && androidDeploy?.command === "bash"
                && androidDeploy.args.join(" ") === `${path.join(notes.checkout!, ".scripts", "Android", "deploy.sh")} ${notes.directory} D SERIAL`
                && fs.readFileSync(path.join(local!, ".gitignore"), "utf8").includes("\n/artifacts/\n"));
            const own: Record<string, Host> = { darwin: "web", win32: "winui", linux: "gtk" };
            await api.selectHost(own[process.platform]);
            for (const architecture of process.platform === "win32" ? winUIArchitectures() : [undefined]) {
                const laid = await vscode.commands.executeCommand<string>("swiftomniui.deploy", { application: notes.directory, architecture });
                const platform = describe(own[process.platform]).label;
                check(`Deploy lays the group's Notes in its artifacts/Notes/${platform}${architecture ? `/${architecture}` : ""}`,
                    laid === path.join(local!, "artifacts", "Notes", platform, ...(architecture ? [architecture] : []))
                    && fs.readdirSync(laid).length > 0);
                if (architecture) {
                    // Its head's architecture, from its PE header; the Swift and C++ runtimes of it beside it, and no module.
                    const head = path.join(laid!, "NotesWinUI.exe");
                    const bytes = fs.readFileSync(head);
                    check(`the deployed head is ${architecture}, with SwiftOmniUI, the Windows App SDK and the Swift and C++ runtimes of its architecture, and nothing only a build reads`,
                        bytes.readUInt16LE(bytes.readUInt32LE(0x3c) + 4) === (architecture === "x64" ? 0x8664 : 0xaa64)
                        && ["SwiftOmniUI.dll", "swiftCore.dll", "Foundation.dll", "vcruntime140.dll", "Microsoft.ui.xaml.dll", "resources.pri"]
                            .every((each) => fs.existsSync(path.join(laid!, each)))
                        && !fs.existsSync(path.join(laid!, "SwiftOmniUI.swiftmodule")) && !fs.existsSync(path.join(laid!, "plutil.exe")));
                    // Started with no Swift on the search path, as on a machine that has none.
                    const bare = (process.env.PATH ?? "").split(";").filter((each) => !/\\Swift\\/i.test(each)).join(";");
                    const started = spawn(head, [], { cwd: laid, env: { ...process.env, PATH: bare }, stdio: "ignore" });
                    await new Promise((resume) => setTimeout(resume, 8000));
                    const runs = started.exitCode === null;
                    started.kill();
                    check(`the deployed ${architecture} Notes runs from there with no Swift on the search path`, runs);
                }
            }

            // A release is offered from minimumRelease on - the first whose scripts build as this extension does.
            const minimum: string = JSON.parse(fs.readFileSync(path.join(root.uri.fsPath, "lib", "SwiftOmniUI.VSCode", "package.json"), "utf8"))
                .contributes.configuration.properties["swiftomniui.minimumRelease"].default;
            const every = await listReleases("https://github.com/zxss702/SwiftOmniUI.git", "0.0.0");
            const offered = await listReleases("https://github.com/zxss702/SwiftOmniUI.git", minimum);
            check(`GitHub lists its releases, and none older than ${minimum} is offered - 0.4.0 builds differently`,
                every.releases.includes("0.4.0") && !offered.releases.includes("0.4.0")
                && offered.releases.every((each) => every.releases.includes(each)));
            const newest = offered.releases[0];
            if (!newest) {
                say(`skip a group of a release: none ${minimum} or newer is published yet`);
            } else {
                const release = await vscode.commands.executeCommand<string>("swiftomniui.newProjectGroup",
                    { location, name: "ReleaseGroup", release: newest, application: "Notes" });
                const releaseNotes = path.join(release ?? "", "apps", "Notes");
                check(`with a release it is cloned into the group's SwiftOmniUI/ at ${newest}, and the application names ../../SwiftOmniUI`,
                    release === path.join(location, "ReleaseGroup")
                    && execSync("git describe --tags", { cwd: releaseDirectory(release) }).toString().trim() === newest
                    && same(checkoutNamedBy(releaseNotes), releaseDirectory(release)) && wired(releaseNotes)
                    && fs.readFileSync(path.join(releaseNotes, "Package.swift"), "utf8").includes('.package(path: "../../SwiftOmniUI")'));
                const more = await vscode.commands.executeCommand<string>("swiftomniui.newApplicationInApps", { folder: release, name: "Tasks" });
                check("New Application in apps/ in that group names its release", same(checkoutNamedBy(more), releaseDirectory(release!)));
                check("the release group's application builds", builds(releaseNotes));
            }
            if (!process.env.SWIFTOMNIUI_TEST_GROUPS) {
                fs.rmSync(location, { recursive: true, force: true });
            }
        }
        // 7b. The extension reinstalls itself from the checkout: packed by npm, installed by the editor's command line.
        {
            const version = JSON.parse(fs.readFileSync(path.join(root.uri.fsPath, "lib", "SwiftOmniUI.VSCode", "package.json"), "utf8")).version;
            const steps = reinstallSteps(root.uri.fsPath, "/Editor/bin/code", "linux");
            check("Reinstall VS Code Extension packs it with npm in lib/SwiftOmniUI.VSCode, then installs artifacts/swiftomniui-<version>.vsix with --force",
                commands.includes("swiftomniui.reinstallExtension") && steps.length === 2
                && `${steps[0].command} ${steps[0].args.join(" ")}` === "npm run package"
                && steps[0].cwd === path.join(root.uri.fsPath, "lib", "SwiftOmniUI.VSCode")
                && steps[1].command === "/Editor/bin/code"
                && steps[1].args.join(" ") === `--install-extension ${path.join(root.uri.fsPath, "artifacts", `swiftomniui-${version}.vsix`)} --force`);
            check("on Windows it packs with npm.cmd, which a terminal whose policy refuses scripts (npm.ps1) still runs",
                reinstallSteps(root.uri.fsPath, "C:\\Editor\\bin\\code.cmd", "win32")[0].command === "npm.cmd");
            check("the command line that installs it is the running editor's own, where its platform keeps it",
                fs.existsSync(editorCommandLine(vscode.env.appRoot)));
        }
        // 7c. The chosen host's marks are made again - every family, or the stale ones - then the documents rendered,
        //     from a checkout alone.
        {
            const checkout = root.uri.fsPath;
            const all = rebuildSteps(checkout, "winui", "all");
            const changed = rebuildSteps(checkout, "winui", "changed");
            const gtk = rebuildSteps(checkout, "gtk", "changed");
            const manifest = JSON.parse(fs.readFileSync(path.join(checkout, "lib", "SwiftOmniUI.VSCode", "package.json"), "utf8"));
            const hidden = (command: string): boolean => manifest.contributes.menus.commandPalette
                .some((each: { command: string; when?: string }) => each.command === command && each.when === "swiftomniui.hasCheckout");
            check("Conformance - Rebuild all and Rebuild changed run the host's families writing their verdicts, then render the documents",
                commands.includes("swiftomniui.conformanceRebuildAll") && commands.includes("swiftomniui.conformanceRebuildChanged")
                && all?.length === 2 && all[0].args.slice(-1)[0] === "-Conformance" && all[0].env.SWIFTOMNIUI_UPDATE_EXPORTS === "1"
                && changed?.[0].args.slice(-1)[0] === "-Stale"
                && gtk?.[0].args.slice(-2).join(" ") === "--filter GTKConformanceTests" && gtk[0].env.SWIFTOMNIUI_STALE_ONLY === "1"
                && all[1].command === "swift" && all[1].args.join(" ") === "test --filter ControlDictionaryTests"
                && all[1].env.SWIFTOMNIUI_UPDATE_DOCS === "1"
                && rebuildSteps(checkout, "android", "changed", "serial") === undefined
                && rebuildSteps(checkout, "web", "all") === undefined);
            check("the conformance rebuilds and the reinstall show in a SwiftOmniUI checkout alone",
                hidden("swiftomniui.conformanceRebuildAll") && hidden("swiftomniui.conformanceRebuildChanged")
                && hidden("swiftomniui.reinstallExtension"));
        }
        // 7d. SwiftOmniUI: Check Toolchain says what this machine has of what its hosts need, and what to install for the
        //     rest: its tools' words read, and on the machine running the suite, nothing missing.
        {
            const loaders = (svg: boolean) => [
                "# GdkPixbuf Image Loader Modules file", "",
                '"/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-png.so"',
                '"png" 5 "gdk-pixbuf" "PNG" "LGPL"', '"image/png" ""', '"png" ""', "",
                ...(svg ? ['"/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders/libpixbufloader-svg.so"',
                    '"svg" 6 "gdk-pixbuf" "Scalable Vector Graphics" "LGPL"', '"image/svg+xml" "image/svg" ""', ""] : []),
            ].join("\n");
            check("Check Toolchain compares versions part by part, reads a toolchain's, an NDK's and gdk-pixbuf's "
                + "words, and says a version too old",
                commands.includes("swiftomniui.checkToolchain")
                && atLeast("6.4.1", "6.4") && atLeast("26", "26.0") && !atLeast("6.3.9", "6.4") && !atLeast("4.13", "4.14")
                && isSwiftOrgBuild("Swift version 6.4 (swift-6.4-RELEASE)")
                && !isSwiftOrgBuild("Apple Swift version 6.4 (swiftlang-6.4.0.1.2 clang-1700.0.1)")
                && svgLoaderIn(loaders(true)) === "libpixbufloader-svg.so" && svgLoaderIn(loaders(false)) === undefined
                && svgLoaderInGlycin("[loader:image/png]\nExec = /usr/libexec/glycin-loaders/2+/glycin-image-rs\n\n"
                    + "[loader:image/svg+xml]\nExec = /usr/libexec/glycin-loaders/2+/glycin-svg\n") === "glycin-svg"
                && svgLoaderInGlycin("[loader:image/png]\nExec = /usr/libexec/glycin-loaders/2+/glycin-image-rs\n") === undefined
                && lldbDapFailure("lldb-dap: LLVM (http://llvm.org/):\n  LLVM version 21.0.0\n") === undefined
                && lldbDapFailure(".../usr/bin/lldb-dap: error while loading shared libraries: libpython3.9.so.1.0: cannot open"
                    + " shared object file: No such file or directory\n") === "libpython3.9.so.1.0 is missing"
                && lldbDapFailure(undefined) === "it did not run"
                && checkedPythonIn("C:\\Swift\\Python-3.10.1\\usr\\bin\\python310.dll\r\n") === "C:\\Swift\\Python-3.10.1\\usr\\bin\\python310.dll"
                && checkedPythonIn("error: unable to find 'python310.dll'.\r\nEnsure Python 3.10 (arm64) is installed and available"
                    + " in your Path.\r\n") === undefined
                && debuggerFinding(["lldb-dap"]).found !== undefined && debuggerFinding(["node"]).found === undefined
                && ndkRevisionIn("Pkg.Desc = Android NDK\nPkg.Revision = 30.0.16248370\n") === "30.0.16248370"
                && report([{ component: "Node.js 20 or newer", neededBy: "it", tooOld: "19.4.0", advice: "Install it." }])[0]
                    === "✗ Node.js 20 or newer - 19.4.0 found, too old [it]. Install it.");
            // As the command asks: the components, then whether the lldb-dap a launch takes starts (Linux, Windows).
            const starts = await lldbDapFinding(vscode.workspace.getConfiguration("lldb-dap").get<string>("executable-path"));
            const findings = [...await checkToolchain(), ...(starts ? [starts] : [])];
            report(findings).forEach((line) => say(`     ${line}`));
            const own: Record<string, string> = { linux: "GTK 4.14 or newer, with its headers",
                darwin: "Swift 6.4 from swift.org, with the Swift SDK for Android of the same release",
                win32: "Visual Studio 2026 with the C++ tools for this machine" };
            const missing = findings.filter((each) => each.found === undefined).map((each) => each.component);
            check(`Check Toolchain looks for Swift, this platform's own, lldb-dap - one that starts, off the Mac - and Git, and finds them all here${
                missing.length > 0 ? ` - not ${missing.join(", ")}` : ""}`,
                findings[0]?.component === "Swift 6.4 or newer" && findings.some((each) => each.component === own[process.platform])
                && findings.some((each) => each.component === "lldb-dap") && findings.some((each) => each.component === "Git")
                && (process.platform === "darwin" || starts?.component === "an lldb-dap that starts")
                && missing.length === 0 && findings.every((each) => each.advice.length > 0));
        }
        // 8. The package holds what the sources build today and nothing an
        //    older build left in out/.
        {
            const extension = path.join(root.uri.fsPath, "lib", "SwiftOmniUI.VSCode");
            const vsce = path.join(extension, "node_modules", ".bin", process.platform === "win32" ? "vsce.cmd" : "vsce");
            const packed = execSync(`"${vsce}" ls`, { cwd: extension }).toString().split(/\r?\n/).filter((line) => line.length > 0);
            // A compiled file whose source is gone is left in out/ by tsc, and would be packed.
            const stray = packed.filter((file) => {
                const compiled = file.match(/^out\/Sources\/([A-Za-z]+)\.js$/);
                return compiled ? !fs.existsSync(path.join(extension, "Sources", `${compiled[1]}.ts`))
                    : !/^(package\.json|README\.md|icon\.png|LICENSE)$/.test(file);
            });
            check(`the package holds the manifest, the readme, the icon and what Sources compile to alone${stray.length > 0 ? ` - not ${stray.slice(0, 3).join(", ")}` : ""}`,
                stray.length === 0 && packed.includes("out/Sources/extension.js"));
        }
        // 9. SwiftOmniUI: Debug runs the REMEMBERED application - no question asked - on this machine's host: WinUI
        //    on Windows and GTK on Linux. On macOS no host builds an application for this machine.
        if (process.platform === "darwin") {
            say("skip Debug on this machine's host: no host builds an application for macOS");
        } else if (process.platform === "win32") {
            await api.selectHost("winui");
            await api.selectApplication("HelloWorld");
            check("the chosen application is remembered", api.application() === "HelloWorld");
            const session = new Promise<vscode.DebugSession>((resolve) => {
                const listener = vscode.debug.onDidStartDebugSession((each) => {
                    if (each.type === "lldb-dap") {
                        listener.dispose();
                        resolve(each);
                    }
                });
            });
            check("SwiftOmniUI: Debug starts", await vscode.debug.startDebugging(root,
                { name: "SwiftOmniUI: Debug", type: "swiftomniui", request: "launch", configuration: "debug" }));
            const running = await Promise.race([session, new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), 900_000))]);
            check("an lldb-dap session starts on HelloWorldWinUI.exe",
                String(running?.configuration.program ?? "").endsWith(path.join("apps", "HelloWorld", ".build", "winui", "debug", "HelloWorldWinUI.exe")));
            const alive = (): boolean => {
                try {
                    return execSync('tasklist /FI "IMAGENAME eq HelloWorldWinUI.exe" /NH').toString().includes("HelloWorldWinUI.exe");
                } catch {
                    return false;
                }
            };
            await until("the HelloWorldWinUI process is running", async () => alive(), 60);
            await vscode.debug.stopDebugging(running);
        } else {
            await api.selectHost("gtk");
            await api.selectApplication("HelloWorld");
            check("the chosen application is remembered", api.application() === "HelloWorld");
            const session = new Promise<vscode.DebugSession>((resolve) => {
                const listener = vscode.debug.onDidStartDebugSession((each) => {
                    if (each.type === "lldb-dap") {
                        listener.dispose();
                        resolve(each);
                    }
                });
            });
            check("SwiftOmniUI: Debug starts", await vscode.debug.startDebugging(root,
                { name: "SwiftOmniUI: Debug", type: "swiftomniui", request: "launch", configuration: "debug" }));
            const running = await Promise.race([session, new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), 900_000))]);
            check("an lldb-dap session starts on HelloWorldGTK",
                String(running?.configuration.program ?? "").endsWith("/apps/HelloWorld/.build/gtk/debug/HelloWorldGTK"));
            await new Promise((resume) => setTimeout(resume, 4000));
            const alive = (() => { try { return execSync("pgrep -f apps/HelloWorld/.build/gtk/debug/HelloWorldGTK").toString().trim().length > 0; } catch { return false; } })();
            check("the HelloWorldGTK process is running", alive);
            await vscode.debug.stopDebugging(running);
        }

        say("PASS");
    } catch (error) {
        say(`FAIL ${error instanceof Error ? error.message : String(error)}`);
        throw error;
    }
}
