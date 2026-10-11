// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The extension: a host and an application chosen once - and for Android a
// device, for the Web a browser - the editor working as that host, one Debug
// and one Release that run the application on it, and the suites run as it.

import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import { Application, findApplications, hasHead, keepsApps } from "./applications";
import { isCheckout } from "./checkouts";
import { configurations, noHost, SwiftOmniUIDebugConfigurationProvider } from "./debug";
import { androidScript, askForDevice, chosenDevice, deviceToRunOn } from "./devices";
import { askForBrowser, Browser, browserToRunOn, chosenBrowser, webScript } from "./browsers";
import { applyEditorMode, cleanIndex, setHostEnvironment, variablesInSettings } from "./editorMode";
import { availableHosts, describe, Host } from "./hosts";
import { readyWhen, runTask, startTask } from "./tasks";
import { findSuites, forDevice, runSuites } from "./tests";
import { checkoutOf, makeApplication, nameProblem } from "./newApplication";
import { cloneRelease, groupNameProblem, listReleases, makeProjectGroup, releaseDirectory } from "./projectGroup";
import { editorCommandLine, hasExtensionSources, reinstallSteps } from "./reinstall";
import { Rebuild, rebuildSteps } from "./conformance";
import { checkToolchain, debuggerFinding, lldbDapFinding, report } from "./toolchain";
import { Architecture, deployCommand, deployDestination, winUIArchitectures } from "./deploy";

/** What the extension answers to another extension - and to its own tests. */
export interface SwiftOmniUIApi {
    host(): Host | undefined;
    selectHost(host: Host): Promise<void>;
    application(): string | undefined;
    selectApplication(name: string): Promise<void>;
}

const hostKey = "swiftomniui.host";
const applicationKey = "swiftomniui.application";

/** What gives an application each host's head. */
const heads: Record<Host, string> = {
    android: "an Android head (Platforms/Android/build.gradle.kts)",
    winui: "a WinUI head (Platforms/WinUI/main.swift)",
    gtk: "a GTK head (Platforms/GTK/main.swift)",
    web: "a Web head (Platforms/Web/main.swift)",
};

export async function activate(context: vscode.ExtensionContext): Promise<SwiftOmniUIApi> {
    const state = context.workspaceState;

    const applications = (): Application[] =>
        (vscode.workspace.workspaceFolders ?? []).flatMap((folder) => findApplications(folder.uri.fsPath));

    /** The applications that have a head for `host`. */
    const runnable = (host: Host): Application[] => applications().filter((each) => hasHead(each, host));

    // Both the library root and its consumers select targets with the host variable.
    const roots = (): string[] => [...new Set([
        ...applications().flatMap((each) => [each.directory, ...(each.checkout ? [each.checkout] : [])]),
        ...(vscode.workspace.workspaceFolders ?? []).map((each) => each.uri.fsPath).filter(isCheckout),
    ])];

    // The one chosen, where this machine runs it; else the first this machine
    // runs that an application here has a head for; none where it runs none.
    const host = (): Host | undefined => {
        const available = availableHosts();
        const stored = state.get<Host>(hostKey);
        if (available.some((each) => each.id === stored)) {
            return stored;
        }
        return (available.find((each) => runnable(each.id).length > 0) ?? available[0])?.id;
    };
    setHostEnvironment(host());

    /** What the suites and the editor run as: the host chosen, or plain Swift. */
    const runningAs = (): string => {
        const chosenHost = host();
        return chosenHost ? describe(chosenHost).label : "plain Swift";
    };

    /** The chosen application, where it still has a head for the chosen host. */
    const chosen = (): Application | undefined => {
        const chosenHost = host();
        return chosenHost ? runnable(chosenHost).find((each) => each.name === state.get<string>(applicationKey)) : undefined;
    };

    const hostItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 50);
    hostItem.command = "swiftomniui.selectHost";
    const applicationItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 49);
    applicationItem.command = "swiftomniui.selectApplication";
    const deviceItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 48);
    deviceItem.command = "swiftomniui.selectAndroidDevice";
    context.subscriptions.push(hostItem, applicationItem, deviceItem);

    // What SwiftOmniUI: Check Toolchain found, component by component.
    const toolchain = vscode.window.createOutputChannel("SwiftOmniUI Toolchain");
    context.subscriptions.push(toolchain);

    // What the scaffolder and git said while making an application or a project group.
    const scaffolder = vscode.window.createOutputChannel("SwiftOmniUI Scaffolder");
    context.subscriptions.push(scaffolder);

    /** The repository a release is cloned from: the one the extension's manifest names. */
    const repository: string = context.extension.packageJSON.repository.url;

    /**
     * The local SwiftOmniUI checkout: a folder open here that is one, else the one
     * `swiftomniui.checkout` names, else asked for.
     */
    const localCheckout = async (): Promise<string | undefined> => {
        const open = (vscode.workspace.workspaceFolders ?? []).map((each) => each.uri.fsPath).find(isCheckout);
        if (open) {
            return open;
        }
        const configured = vscode.workspace.getConfiguration("swiftomniui").get<string>("checkout", "").trim()
            .replace(/^~(?=$|[\\/])/, os.homedir());
        if (configured && isCheckout(configured)) {
            return configured;
        }
        if (configured) {
            void vscode.window.showWarningMessage(`SwiftOmniUI: swiftomniui.checkout names ${configured}, which is not a SwiftOmniUI checkout.`);
        }
        const picked = (await vscode.window.showOpenDialog({
            canSelectFolders: true, canSelectFiles: false, canSelectMany: false,
            title: "Where is the SwiftOmniUI checkout? (swiftomniui.checkout in Settings saves this question)", openLabel: "Use This Checkout",
        }))?.[0]?.fsPath;
        if (picked && !isCheckout(picked)) {
            void vscode.window.showErrorMessage(`SwiftOmniUI: ${picked} is not a SwiftOmniUI checkout - it has no .scripts/new-app.sh and apps/HelloWorld.`);
            return undefined;
        }
        return picked;
    };

    /** Asks for the name of an application made in `apps`. */
    const askApplicationName = (apps: string, title: string): Thenable<string | undefined> => vscode.window.showInputBox({
        title,
        prompt: "The application's name: its directory, process and Swift module (<Name>UI).",
        placeHolder: "MyApp",
        ignoreFocusOut: true,
        validateInput: (value) => nameProblem(value) ?? (fs.existsSync(path.join(apps, value)) ? `apps/${value} already exists.` : undefined),
    });

    /** What went wrong, said with the scaffolder's output, which says why. */
    const reportFailure = (message: string): void => {
        scaffolder.show(true);
        void vscode.window.showErrorMessage(`SwiftOmniUI: ${message} - the SwiftOmniUI Scaffolder output says why.`);
    };

    const refresh = (): void => {
        const chosenHost = host();
        if (!chosenHost) {
            hostItem.text = "$(server-environment) SwiftOmniUI: no host";
            hostItem.tooltip = `SwiftOmniUI: ${noHost} SwiftOmniUI: Run Tests and the editor work as plain Swift.`;
            hostItem.show();
            applicationItem.hide();
            deviceItem.hide();
            return;
        }

        const described = describe(chosenHost);
        hostItem.text = `$(server-environment) SwiftOmniUI: ${described.label}`;
        hostItem.tooltip = `SwiftOmniUI: Debug, SwiftOmniUI: Release, SwiftOmniUI: Run Tests and the editor work as ${described.label} - ${described.detail}. Click to change.`;
        hostItem.show();

        const candidates = runnable(chosenHost);
        const application = chosen() ?? (candidates.length === 1 ? candidates[0] : undefined);
        applicationItem.text = `$(window) ${application?.name ?? "Select Application"}`;
        applicationItem.tooltip = `The application SwiftOmniUI: Debug and SwiftOmniUI: Release run on ${described.label}. Click to change.`;
        candidates.length > 0 ? applicationItem.show() : applicationItem.hide();

        if (described.id === "web") {
            const browser = chosenBrowser(state);
            deviceItem.command = "swiftomniui.selectBrowser";
            deviceItem.text = `$(globe) ${browser?.name ?? "Select Browser"}`;
            deviceItem.tooltip = "The browser SwiftOmniUI: Debug and SwiftOmniUI: Release open the application in - one of Chromium's under VS Code's debugger. Click to change.";
        } else {
            const device = chosenDevice(state);
            deviceItem.command = "swiftomniui.selectAndroidDevice";
            deviceItem.text = `$(device-mobile) ${device?.name ?? "Select Android Device"}`;
            deviceItem.tooltip = `The Android device SwiftOmniUI: Debug, SwiftOmniUI: Release and SwiftOmniUI: Run Tests run on${device ? ` - ${device.serial}` : ""}. Click to change.`;
        }
        ["android", "web"].includes(described.id) ? deviceItem.show() : deviceItem.hide();
    };

    const selectHost = async (picked: Host): Promise<void> => {
        await state.update(hostKey, picked);
        refresh();

        if (await applyEditorMode(picked, roots())) {
            void vscode.window.setStatusBarMessage(`SwiftOmniUI: the editor works as ${describe(picked).label}`, 4000);
        }
    };

    const selectApplication = async (name: string): Promise<void> => {
        await state.update(applicationKey, name);
        refresh();
    };

    /** Asks for an application with a head for `forHost`, the chosen one offered first. */
    const askForApplication = async (forHost: Host): Promise<Application | undefined> => {
        const candidates = runnable(forHost);
        if (candidates.length === 0) {
            void vscode.window.showErrorMessage(`SwiftOmniUI: no application here has ${heads[forHost]}.`);
            return undefined;
        }

        const current = state.get<string>(applicationKey);
        const ordered = [...candidates].sort((a, b) => Number(b.name === current) - Number(a.name === current));
        const picked = await vscode.window.showQuickPick(
            ordered.map((each) => ({
                label: each.name,
                description: each.name === current ? "current" : undefined,
                detail: vscode.workspace.asRelativePath(each.directory),
                application: each,
            })),
            { placeHolder: `Which application do SwiftOmniUI: Debug and SwiftOmniUI: Release run on ${describe(forHost).label}?`, ignoreFocusOut: true });

        if (picked) {
            await selectApplication(picked.application.name);
        }
        return picked?.application;
    };

    /** The Android device a launch or a suite runs on - asked for where none chosen is attached. */
    const androidDevice = async (root: string): Promise<string | undefined> => {
        const serial = await deviceToRunOn(root, state);
        refresh();
        return serial;
    };

    /** The browser a Web launch opens the page in - asked for where none chosen is installed. */
    const browser = async (checkout: string): Promise<Browser | undefined> => {
        const found = await browserToRunOn(checkout, state);
        refresh();
        return found;
    };

    /** The chosen host's marks made again in the checkout - `rebuild` says which families - and the documents rendered. */
    const rebuildConformance = async (rebuild: Rebuild): Promise<void> => {
        const folder = (vscode.workspace.workspaceFolders ?? []).find((each) => isCheckout(each.uri.fsPath));
        const chosen = host();
        if (!folder || !chosen) {
            void vscode.window.showErrorMessage(`SwiftOmniUI: the marks are made in a SwiftOmniUI checkout, as the host chosen - ${folder ? noHost : "no folder here is one"}.`);
            return;
        }
        if (chosen === "web") {
            void vscode.window.showInformationMessage("SwiftOmniUI: the Web host has no conformance driver yet, so it makes no marks.");
            return;
        }
        if (chosen === "android" && rebuild === "changed") {
            void vscode.window.showInformationMessage("SwiftOmniUI: Android's device reads no repository, so its marks are made again whole - Conformance - Rebuild all.");
            return;
        }
        const device = chosen === "android" ? await androidDevice(folder.uri.fsPath) : undefined;
        const steps = rebuildSteps(folder.uri.fsPath, chosen, rebuild, device);
        if (!steps) {
            return;
        }
        for (const step of steps) {
            const task = new vscode.Task({ type: "swiftomniui", suite: `conformance ${rebuild}` }, folder,
                `Conformance - Rebuild ${rebuild}: ${path.basename(step.args.find((each) => each.includes(path.sep)) ?? step.command)}`, "SwiftOmniUI",
                new vscode.ShellExecution(step.command, [...step.args], { cwd: step.cwd, env: step.env }), []);
            task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated };
            if ((await runTask(task)) !== 0) {
                void vscode.window.showErrorMessage(`SwiftOmniUI: ${describe(chosen).label}'s marks were not made again - the terminal says why.`);
                return;
            }
        }
        void vscode.window.showInformationMessage(`SwiftOmniUI: ${describe(chosen).label}'s marks are made again, and the documents rendered from them.`);
    };

    context.subscriptions.push(
        vscode.commands.registerCommand("swiftomniui.conformanceRebuildAll", () => rebuildConformance("all")),
        vscode.commands.registerCommand("swiftomniui.conformanceRebuildChanged", () => rebuildConformance("changed")),
        vscode.commands.registerCommand("swiftomniui.selectHost", async () => {
            if (availableHosts().length === 0) {
                void vscode.window.showInformationMessage(`SwiftOmniUI: ${noHost}`);
                return;
            }
            const picked = await vscode.window.showQuickPick(
                // Android and the Web are offered where an application has their head.
                availableHosts().filter((each) => !["android", "web"].includes(each.id) || runnable(each.id).length > 0).map((each) => ({
                    label: each.label,
                    description: each.id === host() ? "current" : undefined,
                    detail: each.detail,
                    id: each.id,
                })),
                { placeHolder: "Which host do SwiftOmniUI: Debug, SwiftOmniUI: Run Tests and the editor work as?" });
            if (picked) {
                await selectHost(picked.id);
            }
        }),
        vscode.commands.registerCommand("swiftomniui.selectApplication", async () => {
            const chosenHost = host();
            if (!chosenHost) {
                void vscode.window.showInformationMessage(`SwiftOmniUI: ${noHost}`);
                return undefined;
            }
            return askForApplication(chosenHost);
        }),
        vscode.commands.registerCommand("swiftomniui.selectAndroidDevice", async () => {
            const checkout = [chosen()?.checkout, ...applications().map((each) => each.checkout)]
                .find((each): each is string => each !== undefined && fs.existsSync(androidScript(each, "devices.sh")));
            if (!checkout) {
                void vscode.window.showErrorMessage("SwiftOmniUI: Android devices are listed by a SwiftOmniUI checkout's .scripts/Android/devices.sh, and no application here names one.");
                return;
            }
            await askForDevice(checkout, state);
            refresh();
        }),
        vscode.commands.registerCommand("swiftomniui.selectBrowser", async () => {
            const checkout = [chosen()?.checkout, ...applications().map((each) => each.checkout)]
                .find((each): each is string => each !== undefined && fs.existsSync(webScript(each, "browsers.sh")));
            if (!checkout) {
                void vscode.window.showErrorMessage("SwiftOmniUI: browsers are listed by a SwiftOmniUI checkout's .scripts/Web/browsers.sh, and no application here names one.");
                return;
            }
            await askForBrowser(checkout, state);
            refresh();
        }),
        vscode.commands.registerCommand("swiftomniui.runTests", async () => {
            const folder = vscode.workspace.workspaceFolders?.[0];
            const suites = folder ? findSuites(folder.uri.fsPath, host()) : [];
            if (!folder || suites.length === 0) {
                void vscode.window.showInformationMessage(`SwiftOmniUI: no test suite here runs as ${runningAs()}.`);
                return;
            }

            const picked = await vscode.window.showQuickPick(
                suites.map((suite) => ({ label: suite.label, detail: suite.detail, picked: true, suite })),
                { canPickMany: true, placeHolder: `The suites to run as ${runningAs()}` });
            if (!picked || picked.length === 0) {
                return;
            }

            let chosenSuites = picked.map((each) => each.suite);
            if (chosenSuites.some((each) => each.onDevice)) {
                const serial = await androidDevice(folder.uri.fsPath);
                if (!serial) {
                    return;
                }
                chosenSuites = chosenSuites.map((each) => forDevice(each, serial));
            }

            const failed = await runSuites(folder, chosenSuites);
            if (failed.length === 0) {
                void vscode.window.showInformationMessage(`SwiftOmniUI: all ${picked.length} suites passed as ${runningAs()}.`);
            } else {
                void vscode.window.showErrorMessage(
                    `SwiftOmniUI: ${failed.length} of ${picked.length} suites failed as ${runningAs()}: ${failed.join(", ")}. Their output is in the terminal.`);
            }
        }),
        vscode.commands.registerCommand("swiftomniui.newApplicationInApps", async (given?: { folder?: string; name?: string }) => {
            const keeping = (vscode.workspace.workspaceFolders ?? []).filter((each) => keepsApps(each.uri.fsPath));
            const folder = given?.folder ?? (keeping.length > 1
                ? (await vscode.window.showWorkspaceFolderPick({ placeHolder: "Which folder's apps/ is the application made in?" }))?.uri.fsPath
                : keeping[0]?.uri.fsPath);
            if (!folder || !keepsApps(folder)) {
                void vscode.window.showErrorMessage("SwiftOmniUI: no folder here keeps applications in apps/ - a SwiftOmniUI checkout or a project group does.");
                return undefined;
            }

            // The checkout its applications build with; in a group whose apps/ holds none yet, the local one.
            const checkout = checkoutOf(folder) ?? await localCheckout();
            if (!checkout) {
                return undefined;
            }
            const apps = path.join(folder, "apps");
            const name = given?.name ?? await askApplicationName(apps, "New Application in apps/");
            if (!name) {
                return undefined;
            }

            const made = await makeApplication(checkout, apps, name);
            scaffolder.appendLine(made.output);
            if (!made.made) {
                reportFailure(`${name} was not made`);
                return undefined;
            }

            // Runnable at once: chosen, and indexed as the host the editor works as.
            await selectApplication(name);
            await applyEditorMode(host(), roots());
            void vscode.window.showInformationMessage(`SwiftOmniUI: apps/${name} is made and chosen - SwiftOmniUI: Debug runs it.`);
            return path.join(apps, name);
        }),
        vscode.commands.registerCommand("swiftomniui.newProjectGroup", async (given?: {
            location?: string; name?: string; release?: string; checkout?: string; application?: string;
        }) => {
            const location = given?.location ?? (await vscode.window.showOpenDialog({
                canSelectFolders: true, canSelectFiles: false, canSelectMany: false,
                title: "New Project Group: where is it made?", openLabel: "Make the Group Here",
            }))?.[0]?.fsPath;
            if (!location) {
                return undefined;
            }
            const taken = (value: string): string | undefined =>
                groupNameProblem(value) ?? (fs.existsSync(path.join(location, value)) ? `${path.join(location, value)} already exists.` : undefined);
            const name = given?.name ?? await vscode.window.showInputBox({
                title: "New Project Group",
                prompt: `The group's folder, made in ${location}: apps/, and what git and the editor need beside it.`,
                placeHolder: "MyApps",
                ignoreFocusOut: true,
                validateInput: taken,
            });
            if (!name) {
                return undefined;
            }
            if (taken(name)) {
                void vscode.window.showErrorMessage(`SwiftOmniUI: ${taken(name)}`);
                return undefined;
            }
            const group = path.join(location, name);

            // Where its SwiftOmniUI comes from: a release cloned into the group, or the local checkout.
            const minimum = vscode.workspace.getConfiguration("swiftomniui").get<string>("minimumRelease", "0.5.0");
            let release = given?.release;
            let checkout = given?.checkout;
            if (!release && !checkout) {
                const source = await vscode.window.showQuickPick([
                    { label: "A release from GitHub", detail: `A release, ${minimum} or newer, cloned into the group's SwiftOmniUI/.`, release: true },
                    { label: "The local checkout", detail: "The SwiftOmniUI checkout open here, else the one swiftomniui.checkout names, else asked for.", release: false },
                ], { title: "New Project Group", placeHolder: "Which SwiftOmniUI do the group's applications build with?", ignoreFocusOut: true });
                if (!source) {
                    return undefined;
                }
                if (source.release) {
                    const listed = await vscode.window.withProgress(
                        { location: vscode.ProgressLocation.Notification, title: `SwiftOmniUI: reading the releases of ${repository}` },
                        () => listReleases(repository, minimum));
                    if (listed.problem) {
                        scaffolder.appendLine(listed.problem);
                        reportFailure(`the releases of ${repository} were not read`);
                        return undefined;
                    }
                    if (listed.releases.length === 0) {
                        void vscode.window.showWarningMessage(
                            `SwiftOmniUI: no release ${minimum} or newer is published yet - an older one builds differently from this extension. The local checkout builds with it.`);
                        return undefined;
                    }
                    release = await vscode.window.showQuickPick(listed.releases, {
                        title: "New Project Group", placeHolder: `The release the group's applications build with - ${minimum} or newer`, ignoreFocusOut: true,
                    });
                    if (!release) {
                        return undefined;
                    }
                } else {
                    checkout = await localCheckout();
                    if (!checkout) {
                        return undefined;
                    }
                }
            }
            if (checkout && !isCheckout(checkout)) {
                void vscode.window.showErrorMessage(`SwiftOmniUI: ${checkout} is not a SwiftOmniUI checkout - it has no .scripts/new-app.sh and apps/HelloWorld.`);
                return undefined;
            }

            const library = release ? releaseDirectory(group) : checkout;
            const application = given?.application ?? await askApplicationName(path.join(group, "apps"), "New Project Group: its first application");
            if (!library || !application) {
                return undefined;
            }

            const made = await vscode.window.withProgress(
                { location: vscode.ProgressLocation.Notification, title: `SwiftOmniUI: making ${name}` },
                async (progress) => {
                    makeProjectGroup(group, repository);
                    if (release) {
                        progress.report({ message: `cloning SwiftOmniUI ${release}` });
                        const cloned = await cloneRelease(repository, release, group);
                        scaffolder.appendLine(cloned.output);
                        if (!cloned.cloned) {
                            reportFailure(`SwiftOmniUI ${release} was not cloned into ${group}`);
                            return false;
                        }
                    }
                    progress.report({ message: `making apps/${application}` });
                    const scaffolded = await makeApplication(library, path.join(group, "apps"), application);
                    scaffolder.appendLine(scaffolded.output);
                    if (!scaffolded.made) {
                        reportFailure(`${application} was not made in ${group}`);
                    }
                    return scaffolded.made;
                });
            if (!made) {
                return undefined;
            }

            void vscode.window.showInformationMessage(
                `SwiftOmniUI: ${group} is made, building with ${release ? `SwiftOmniUI ${release}` : checkout}, and holds apps/${application}.`,
                "Open", "Open in New Window").then(async (answer) => {
                    if (answer) {
                        await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(group), { forceNewWindow: answer === "Open in New Window" });
                    }
                });
            return group;
        }),
        vscode.commands.registerCommand("swiftomniui.reinstallExtension", async () => {
            const folder = (vscode.workspace.workspaceFolders ?? []).find((each) => hasExtensionSources(each.uri.fsPath));
            if (!folder) {
                void vscode.window.showErrorMessage("SwiftOmniUI: the extension is built from a SwiftOmniUI checkout's lib/SwiftOmniUI.VSCode, which no folder here has.");
                return;
            }
            for (const step of reinstallSteps(folder.uri.fsPath, editorCommandLine(vscode.env.appRoot))) {
                const task = new vscode.Task({ type: "swiftomniui", step: path.basename(step.command) }, folder,
                    `Reinstall the extension: ${path.basename(step.command)} ${step.args[0]}`, "SwiftOmniUI",
                    new vscode.ShellExecution({ value: step.command, quoting: vscode.ShellQuoting.Strong },
                        step.args.map((each) => ({ value: each, quoting: vscode.ShellQuoting.Strong })), { cwd: step.cwd }), []);
                task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated };
                if ((await runTask(task)) !== 0) {
                    void vscode.window.showErrorMessage(`SwiftOmniUI: the extension was not reinstalled - the terminal says why.`);
                    return;
                }
            }
            const answer = await vscode.window.showInformationMessage(
                "SwiftOmniUI: the extension is built and installed - reload the window to run it.", "Reload Window");
            if (answer) {
                await vscode.commands.executeCommand("workbench.action.reloadWindow");
            }
        }),
        vscode.commands.registerCommand("swiftomniui.checkToolchain", async () => {
            const findings = await vscode.window.withProgress(
                { location: vscode.ProgressLocation.Notification, title: "SwiftOmniUI: checking the toolchain" },
                () => checkToolchain());
            const types = vscode.extensions.all.flatMap((each) =>
                ((each.packageJSON?.contributes?.debuggers ?? []) as { type?: string }[]).map((debug) => debug.type ?? ""));
            const starts = await lldbDapFinding(vscode.workspace.getConfiguration("lldb-dap").get<string>("executable-path"));
            const all = [...findings, debuggerFinding(types), ...(starts ? [starts] : [])];
            const served = availableHosts().map((each) => each.label).join(", ");
            toolchain.clear();
            toolchain.appendLine(`What ${served || "SwiftOmniUI"} needs on this machine (${process.platform}, ${process.arch}):`);
            report(all).forEach((line) => toolchain.appendLine(line));
            toolchain.show(true);
            const missing = all.filter((each) => each.found === undefined).length;
            if (missing === 0) {
                void vscode.window.showInformationMessage(`SwiftOmniUI: everything ${served || "SwiftOmniUI"} needs is here.`);
            } else {
                void vscode.window.showWarningMessage(
                    `SwiftOmniUI: ${missing} of ${all.length} components are missing - the output says what to install.`);
            }
        }),
        // The answers can come as an argument - the application's folder, the architecture - as the suite gives them.
        vscode.commands.registerCommand("swiftomniui.deploy", async (asked?: { application?: string; architecture?: Architecture }) => {
            const forHost = host();
            if (!forHost) {
                void vscode.window.showErrorMessage(`SwiftOmniUI: ${noHost}`);
                return undefined;
            }
            const application = asked?.application
                ? findApplications(path.dirname(path.dirname(asked.application))).find((each) => each.directory === asked.application)
                : chosen() ?? await askForApplication(forHost);
            if (!application) {
                return undefined;
            }
            const offered = forHost === "winui" ? winUIArchitectures() : [];
            const architecture = asked?.architecture ?? (offered.length > 1
                ? (await vscode.window.showQuickPick(
                    offered.map((each, index) => ({ label: each, description: index === 0 ? "this machine's own" : "run by Windows' emulation" })),
                    { title: `SwiftOmniUI: Deploy ${application.name} for which architecture?`, ignoreFocusOut: true }))?.label as Architecture | undefined
                : offered[0]);
            if (forHost === "winui" && !architecture) {
                return undefined;
            }
            const device = forHost === "android" && application.checkout ? await androidDevice(application.checkout) : undefined;
            if (forHost === "android" && !device) {
                return undefined;
            }

            const destination = deployDestination(application, forHost, architecture);
            const step = deployCommand(application, forHost, destination, architecture, device);
            if (!step || !fs.existsSync(step.script)) {
                void vscode.window.showErrorMessage(
                    `SwiftOmniUI: ${application.name} is deployed by a SwiftOmniUI checkout's .scripts/${describe(forHost).label}/${path.basename(step?.script ?? "deploy")}, which ${step ? "it does not have" : "its Package.swift names none of by path"}.`);
                return undefined;
            }
            const task = new vscode.Task(
                { type: "swiftomniui", application: application.name, configuration: "release", device: architecture ?? device ?? forHost },
                vscode.TaskScope.Workspace, `Deploy ${application.name} (${describe(forHost).label}${architecture ? `, ${architecture}` : ""})`,
                "SwiftOmniUI", new vscode.ProcessExecution(step.command, step.args, { cwd: path.dirname(path.dirname(application.directory)) }), []);
            task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated };
            if ((await runTask(task)) !== 0) {
                void vscode.window.showErrorMessage(`SwiftOmniUI: ${application.name} was not deployed - the terminal says why.`);
                return undefined;
            }
            void vscode.window.showInformationMessage(`SwiftOmniUI: ${application.name} is deployed in ${destination}.`, "Reveal")
                .then((answer) => answer && vscode.commands.executeCommand("revealFileInOS", vscode.Uri.file(destination)));
            return destination;
        }),
        vscode.commands.registerCommand("swiftomniui.cleanIndex", async () => {
            await cleanIndex(roots());
            void vscode.window.setStatusBarMessage("SwiftOmniUI: the index is being built again", 4000);
        }));

    const provider = new SwiftOmniUIDebugConfigurationProvider({
        host,
        run: runTask,
        start: startTask,
        ready: (file, task) => readyWhen(file, task),
        device: androidDevice,
        browser,
        application: async (_folder, forHost, named) => {
            const candidates = runnable(forHost);

            if (named !== undefined) {
                const found = candidates.find((each) => each.name === named);
                if (!found) {
                    void vscode.window.showErrorMessage(`SwiftOmniUI: no application named ${named} runs on ${describe(forHost).label}.`);
                }
                return found;
            }

            // The chosen one - asked for only when there is none, or when the
            // one chosen has no head for this host.
            const remembered = candidates.find((each) => each.name === state.get<string>(applicationKey));
            if (remembered) {
                return remembered;
            }
            if (candidates.length === 1) {
                await selectApplication(candidates[0].name);
                return candidates[0];
            }
            return askForApplication(forHost);
        },
    });
    context.subscriptions.push(
        vscode.debug.registerDebugConfigurationProvider("swiftomniui", provider),
        vscode.debug.registerDebugConfigurationProvider("swiftomniui", { provideDebugConfigurations: configurations },
            vscode.DebugConfigurationProviderTriggerKind.Dynamic));

    // A settings file that sets a host variable decides the editor's mode over
    // anything chosen here, so it is said once, with the way out.
    const settled = variablesInSettings();
    if (settled.length > 0) {
        void vscode.window.showWarningMessage(
            `SwiftOmniUI: swift.swiftEnvironmentVariables sets ${settled.join(", ")}, which decides the editor's host whatever is chosen in the status bar.`,
            "Remove it").then(async (answer) => {
                if (answer) {
                    const configuration = vscode.workspace.getConfiguration("swift");
                    const inspected = configuration.inspect<Record<string, string>>("swiftEnvironmentVariables");
                    const kept = Object.fromEntries(Object.entries(inspected?.workspaceValue ?? {}).filter(([key]) => !settled.includes(key)));
                    await configuration.update("swiftEnvironmentVariables",
                        Object.keys(kept).length > 0 ? kept : undefined, vscode.ConfigurationTarget.Workspace);
                }
            });
    }

    // A checkout's own commands show in a checkout alone; New Application in apps/ in a checkout or a project group.
    const updateFolderContexts = (): void => {
        const folders = (vscode.workspace.workspaceFolders ?? []).map((folder) => folder.uri.fsPath);
        void vscode.commands.executeCommand("setContext", "swiftomniui.hasCheckout", folders.some(isCheckout));
        void vscode.commands.executeCommand("setContext", "swiftomniui.hasApps", folders.some(keepsApps));
    };
    context.subscriptions.push(vscode.workspace.onDidChangeWorkspaceFolders(updateFolderContexts));
    updateFolderContexts();

    refresh();
    await applyEditorMode(host(), roots());

    return { host, selectHost, application: () => state.get<string>(applicationKey), selectApplication };
}

export function deactivate(): void {}
