// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The applications a workspace holds: a SwiftOmniUI checkout keeps them in apps/,
// and a workspace may be one itself.

import * as fs from "fs";
import * as path from "path";
import { checkoutNamedBy } from "./checkouts";
import { Host } from "./hosts";

/** One application, and the heads it has. */
export interface Application {
    /** The application's name - `Gallery` - which its products are named after. */
    readonly name: string;

    /** The directory holding its Package.swift. */
    readonly directory: string;

    /** Whether it has an Android head: the Gradle build in `Platforms/Android`. */
    readonly hasAndroidHead: boolean;

    /** Whether it has a WinUI head: `Platforms/WinUI/main.swift`. */
    readonly hasWinUIHead: boolean;

    /** Whether it has a GTK head: `Platforms/GTK/main.swift`. */
    readonly hasGTKHead: boolean;

    /** Whether it has a Web head: `Platforms/Web/main.swift`. */
    readonly hasWebHead: boolean;

    /**
     * The SwiftOmniUI checkout its Package.swift names by path, or the one a URL
     * dependency resolved into `.build/checkouts/` - the library it builds with,
     * whose `.scripts` build and run its heads - where it has one.
     */
    readonly checkout?: string;
}

/** The applications under `root`, the workspace itself first. */
export function findApplications(root: string): Application[] {
    const candidates = [root];
    const apps = path.join(root, "apps");

    if (isDirectory(apps)) {
        for (const entry of fs.readdirSync(apps).sort()) {
            candidates.push(path.join(apps, entry));
        }
    }

    return candidates.flatMap((directory) => {
        const application = describeApplication(root, directory);
        return application ? [application] : [];
    });
}

function describeApplication(root: string, directory: string): Application | undefined {
    if (!fs.existsSync(path.join(directory, "Package.swift"))) {
        return undefined;
    }

    const hasAndroidHead = fs.existsSync(path.join(directory, "Platforms", "Android", "build.gradle.kts"));
    const hasWinUIHead = fs.existsSync(path.join(directory, "Platforms", "WinUI", "main.swift"));
    const hasGTKHead = fs.existsSync(path.join(directory, "Platforms", "GTK", "main.swift"));
    const hasWebHead = fs.existsSync(path.join(directory, "Platforms", "Web", "main.swift"));

    if (!hasAndroidHead && !hasWinUIHead && !hasGTKHead && !hasWebHead) {
        return undefined;
    }

    return {
        name: path.basename(directory),
        directory,
        hasAndroidHead,
        hasWinUIHead,
        hasGTKHead,
        hasWebHead,
        checkout: checkoutNamedBy(directory),
    };
}


/** Whether `application` has a head for `host`. */
export function hasHead(application: Application, host: Host): boolean {
    switch (host) {
    case "android": return application.hasAndroidHead;
    case "winui": return application.hasWinUIHead;
    case "gtk": return application.hasGTKHead;
    case "web": return application.hasWebHead;
    }
}

/** Whether `folder` keeps applications in apps/ - a SwiftOmniUI checkout, or a project group. */
export function keepsApps(folder: string): boolean {
    return isDirectory(path.join(folder, "apps"));
}

function isDirectory(candidate: string): boolean {
    return fs.existsSync(candidate) && fs.statSync(candidate).isDirectory();
}

/** Where an application's GTK head is, once `.scripts/GTK/run-app.sh` built it in `configuration`. */
export function gtkProgram(application: Application, configuration: "debug" | "release"): string {
    return path.join(application.directory, ".build", "gtk", configuration, `${application.name}GTK`);
}

/** Where an application's Web page is laid out, once `.scripts/Web/run-app.sh` built it in `configuration`. */
export function webSite(application: Application, configuration: "debug" | "release"): string {
    return path.join(application.directory, ".build", "web", "site", configuration);
}

/** Where an application's WinUI head is, once `.scripts/WinUI/run-app.ps1` built it in `configuration`. */
export function winUIProgram(application: Application, configuration: "debug" | "release"): string {
    return path.join(application.directory, ".build", "winui", configuration, `${application.name}WinUI.exe`);
}
