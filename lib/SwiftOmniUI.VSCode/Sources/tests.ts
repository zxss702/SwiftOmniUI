// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The suites a workspace holds, run AS THE CHOSEN HOST - the same runs CI
// makes, one condition at a time.

import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { findApplications } from "./applications";
import { isCheckout } from "./checkouts";
import { androidScript } from "./devices";
import { describe, Host } from "./hosts";
import { runTask } from "./tasks";

/** One suite, and the command that runs it. */
export interface Suite {
    readonly label: string;
    readonly detail: string;
    readonly command: string;
    readonly args: readonly string[];
    readonly env: Record<string, string>;

    /**
     * Whether it runs on the host's device - an Android device - whose serial
     * ends its arguments once one is chosen.
     */
    readonly onDevice?: boolean;
}

/** Root target suites, platform runners, and each independent application's tests. */
export function findSuites(root: string, host: Host | undefined): Suite[] {
    const suites: Suite[] = [];
    const plain = { SWIFTOMNIUI_HOST: "" };
    if (isCheckout(root)) {
        for (const module of ["SwiftOmniUI", "SwiftOmniUIHost", "SwiftOmniUIFoundation", "SwiftOmniUIJsonData", "SwiftOmniUIConformance"]) {
            suites.push({ label: module, detail: `swift test - ${module}Tests in the root package`, command: "swift",
                args: ["test", "--package-path", root, "--filter", `${module}Tests`], env: plain });
        }
        if (host === "gtk") {
            const module = `SwiftOmniUI${describe(host).label}`;
            suites.push({ label: module, detail: `swift test - ${module}Tests in the root package`, command: "swift",
                args: ["test", "--package-path", root, "--filter", `${module}Tests`], env: { SWIFTOMNIUI_HOST: host } });
        }
        if (host === "winui") {
            suites.push({ label: "SwiftOmniUIWinUI", detail: "WinUI tests with the Windows App SDK beside the root runner",
                command: "powershell", args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    path.join(root, ".scripts", "WinUI", "test-winui.ps1")], env: {} });
        }
        if (host === "web") {
            suites.push({ label: "SwiftOmniUIWeb", detail: "The root Web test target, compiled for WebAssembly",
                command: "bash", args: [path.join(root, ".scripts", "Web", "test-web.sh")], env: {} });
        }
        if (host === "android") {
            suites.push({ label: `lib/SwiftOmniUI.${describe(host).label}/Tests`, detail: "Root test product on the selected device",
                command: "bash", args: [androidScript(root, "test-android.sh")], env: {}, onDevice: true });
        }
    }
    for (const application of findApplications(root)) {
        const directory = application.directory;
        const manifest = path.join(directory, "Package.swift");
        if (!fs.existsSync(manifest) || !fs.readFileSync(manifest, "utf8").includes(".testTarget(")) { continue; }
        const label = directory === root ? path.basename(root) : path.relative(root, directory).split(path.sep).join("/");
        const args = ["test", "--package-path", directory];
        suites.push({ label, detail: "swift test - application", command: "swift", args, env: plain });
    }
    return suites;
}

/** `suite` run on the device `serial` - an Android device's serial - where it runs on one. */
export function forDevice(suite: Suite, serial: string): Suite {
    return suite.onDevice ? { ...suite, args: [...suite.args, serial] } : suite;
}

/**
 * Runs `suites` one after another, each as a task of its own, and answers the
 * labels of those that failed. A failure does not stop the ones after it: the
 * point of running them all is to see all of them.
 */
export async function runSuites(folder: vscode.WorkspaceFolder, suites: readonly Suite[]): Promise<string[]> {
    const failed: string[] = [];

    for (const suite of suites) {
        const task = new vscode.Task(
            { type: "swiftomniui", suite: suite.label }, folder, `Test ${suite.label}`, "SwiftOmniUI",
            new vscode.ShellExecution(suite.command, [...suite.args], { cwd: folder.uri.fsPath, env: suite.env }), []);
        task.group = vscode.TaskGroup.Test;
        task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated };

        if ((await runTask(task)) !== 0) {
            failed.push(suite.label);
        }
    }

    return failed;
}
