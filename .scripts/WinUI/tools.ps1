# Copyright 2026 the SwiftOmniUI project authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ---------------------------------------------------------------------------
# What every WinUI script shares, dot-sourced: the versions of C++/WinRT and
# the Windows App SDK - here and nowhere else - the packages fetched where
# they are missing, the projection the relay includes, and a directory made
# self-contained: the Windows App SDK beside the executables, its classes
# registered in a manifest beside each one, and resources.pri. No MSBuild.
# Design: docs/design/platforms/winui/runtime.md#self-contained
# ---------------------------------------------------------------------------

# Native tools write to stderr as they work; each step is judged by its exit code.
$ErrorActionPreference = 'Continue'

$SwiftOmniUIRepository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$SwiftOmniUIWinUIHost = Join-Path $SwiftOmniUIRepository 'lib\SwiftOmniUI.WinUI'

# Stable Windows App SDK aggregate release. Its components have independent
# versions; these pins are the 2.5.1 dependency graph, with a newer stable
# WebView2 SDK than WinUI's minimum (1.0.3719.77).
$SwiftOmniUIWindowsAppSDKVersion = '2.5.1'
$SwiftOmniUIPackages = [ordered]@{
    'microsoft.windows.cppwinrt'                   = '3.0.260818.1'
    'microsoft.windowsappsdk.base'                 = '2.0.4'
    'microsoft.windowsappsdk.winui'                = '2.3.9'
    'microsoft.windowsappsdk.foundation'           = '2.3.12'
    'microsoft.windowsappsdk.interactiveexperiences' = '2.1.9'
    'microsoft.web.webview2'                       = '1.0.4258.31'
}

$SwiftOmniUIPackageRoot = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { Join-Path $env:USERPROFILE '.nuget\packages' }
# The machine's own, which the toolchain builds for: a PowerShell an emulated shell starts runs as x64 on an ARM64
# machine, and would lay x64 libraries beside ARM64 executables.
$SwiftOmniUIArchitecture = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }

# One package's folder, fetched from nuget.org first where it is missing - its
# SHA-512 checked against the catalog's before a byte of it is unpacked.
function Get-SwiftOmniUIPackage([string]$Id) {
    $version = $SwiftOmniUIPackages[$Id]
    $folder = Join-Path $SwiftOmniUIPackageRoot "$Id\$version"
    if (Test-Path (Join-Path $folder "$Id.nuspec")) { return $folder }

    Write-Host "fetching $Id $version"
    $download = Join-Path $env:TEMP "$Id.$version.nupkg"
    Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/$Id/$version/$Id.$version.nupkg" -OutFile $download
    $registration = Invoke-RestMethod "https://api.nuget.org/v3/registration5-semver1/$Id/$version.json"
    $catalog = Invoke-RestMethod $registration.catalogEntry
    $hash = [Convert]::ToBase64String(
        [System.Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($download)))
    if ($hash -ne $catalog.packageHash) { throw "$Id $version does not match nuget.org's catalog" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force $folder | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($download, $folder)
    Remove-Item $download
    return $folder
}

# The C++/WinRT projection of the Windows SDK, WinUI and the Windows App SDK,
# into the host's .projection/, generated again when the versions change -
# beside it, WinUI's header for drawing with DirectX into its elements.
function Initialize-SwiftOmniUIProjection {
    $projection = Join-Path $SwiftOmniUIWinUIHost '.projection'
    $stamp = Join-Path $projection 'versions.txt'
    $interop = 'microsoft.ui.xaml.media.dxinterop.h'
    $versionHeader = 'SwiftOmniUIWinUIVersion.h'
    $versions = "windowsappsdk $SwiftOmniUIWindowsAppSDKVersion`n" +
        (($SwiftOmniUIPackages.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" }) -join "`n")
    if ((Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $versions.Trim()) -and
        (Test-Path (Join-Path $projection $interop)) -and
        (Test-Path (Join-Path $projection $versionHeader)) -and
        (Test-Path (Join-Path $projection 'winrt\Microsoft.UI.Xaml.Settings.h')) -and
        (Test-Path (Join-Path $projection 'winrt\Microsoft.Windows.ApplicationModel.WindowsAppRuntime.h'))) { return }

    $cppwinrt = Join-Path (Get-SwiftOmniUIPackage 'microsoft.windows.cppwinrt') 'bin\cppwinrt.exe'
    $winui = Get-SwiftOmniUIPackage 'microsoft.windowsappsdk.winui'
    $foundation = Get-SwiftOmniUIPackage 'microsoft.windowsappsdk.foundation'
    $experiences = Get-SwiftOmniUIPackage 'microsoft.windowsappsdk.interactiveexperiences'
    $webview = Get-SwiftOmniUIPackage 'microsoft.web.webview2'

    Write-Host 'generating the C++/WinRT projection'
    if (Test-Path $projection) { Remove-Item -Recurse -Force $projection }
    & $cppwinrt -input sdk -input "$winui\metadata" -input "$foundation\metadata" `
        -input "$experiences\metadata\10.0.18362.0" -input "$webview\lib\Microsoft.Web.WebView2.Core.winmd" `
        -output $projection
    if ($LASTEXITCODE) { throw 'cppwinrt could not generate the projection' }
    Copy-Item (Join-Path $winui "include\$interop") $projection
    $release = [version]$SwiftOmniUIWindowsAppSDKVersion
    Set-Content -Path (Join-Path $projection $versionHeader) -Encoding ascii -Value @"
// Generated from .scripts/WinUI/tools.ps1. Never edit the projected copy.
#pragma once
#define SWIFTOMNIUI_WINDOWS_APP_SDK_MAJOR $($release.Major)
#define SWIFTOMNIUI_WINDOWS_APP_SDK_MINOR $($release.Minor)
#define SWIFTOMNIUI_WINDOWS_APP_SDK_PATCH $($release.Build)
"@
    Set-Content -Path $stamp -Value $versions -Encoding ascii
}

# What SwiftPM is told to build for `Architecture`: nothing for the toolchain's
# own, `--arch` for another - its `--triple` builds the toolchain's own.
function Get-SwiftOmniUIArchitectureArguments([string]$Architecture) {
    if ($Architecture -eq $SwiftOmniUIArchitecture) { return @() }
    return @('--arch', @{ x64 = 'x86_64'; arm64 = 'aarch64' }[$Architecture])
}

# The C++ runtime for `Architecture`, laid in `Directory` - Visual Studio's
# app-local redistributable - which the Swift runtime links.
function Add-SwiftOmniUICppRuntime([string]$Directory, [string]$Architecture) {
    $studio = & (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe') -latest -products * -property installationPath
    $release = Get-ChildItem (Join-Path $studio 'VC\Redist\MSVC') -Directory | Where-Object Name -match '^\d+\.\d+\.\d+$' |
        Sort-Object { [version]$_.Name } | Select-Object -Last 1
    $runtime = Get-ChildItem (Join-Path $release.FullName $Architecture) -Directory -Filter 'Microsoft.VC*.CRT' | Select-Object -First 1
    if (-not $runtime) { throw "no C++ runtime for $Architecture in $($release.FullName)" }
    Copy-Item (Join-Path $runtime.FullName '*.dll') $Directory -Force
}

# Says so when the editor is building for its index: it shares the processor
# with a build, and can make it minutes longer.
function Write-SwiftOmniUIEditorBuilds {
    $builds = Get-CimInstance Win32_Process -Filter "Name = 'swift-build.exe' OR Name = 'swiftc.exe' OR Name = 'clang.exe'" |
        Where-Object { $_.CommandLine -match 'index-build' }
    if ($builds) { Write-Host 'the editor is building for its index, which slows this build' }
}

# Makes `Directory` self-contained for each of `Executables`, built for
# `Architecture`: the Windows App SDK's runtime beside them, what each backend
# linked there needs (lib\Backends\*.WinUI\SelfContained.ps1), the Swift
# runtime where the architecture is not the toolchain's, every class its
# components declare registered in the manifest beside each one, and
# resources.pri. An executable is never rewritten after its build: the next
# build would link it again.
# The selected product's target closure determines which native backends ship.
function Get-SwiftOmniUILinkedBackends([string]$Package, [string]$Product) {
    $json = swift package --package-path $Package dump-package
    if ($LASTEXITCODE) { throw 'the application manifest could not be read' }
    $manifest = ($json -join "`n") | ConvertFrom-Json
    $productTargets = @($manifest.products | Where-Object name -eq $Product | ForEach-Object { $_.targets })
    $pending = [Collections.Generic.Stack[string]]::new()
    if ($productTargets.Count) { foreach ($name in $productTargets) { $pending.Push($name) } }
    else { $pending.Push($Product) } # SwiftPM's implicit executable product.
    $seen = [Collections.Generic.HashSet[string]]::new()
    $linked = [Collections.Generic.HashSet[string]]::new()
    while ($pending.Count) {
        $name = $pending.Pop()
        if (-not $seen.Add($name)) { continue }
        if ($name -eq 'SwiftOmniUIWebViewWinUI') { $linked.Add($name) | Out-Null }
        $target = $manifest.targets | Where-Object name -eq $name
        foreach ($dependency in $target.dependencies) {
            if ($dependency.product) {
                if ($dependency.product[0] -eq 'SwiftOmniUIWebViewWinUI') { $linked.Add($dependency.product[0]) | Out-Null }
            } elseif ($dependency.target) { $pending.Push($dependency.target[0]) }
            elseif ($dependency.byName) { $pending.Push($dependency.byName[0]) }
        }
    }
    return @($linked)
}

function Set-SwiftOmniUISelfContained([string]$Directory, [string[]]$Executables, [string]$Architecture = $SwiftOmniUIArchitecture, [string[]]$Backends = @()) {
    $components = 'microsoft.windowsappsdk.winui', 'microsoft.windowsappsdk.foundation',
        'microsoft.windowsappsdk.interactiveexperiences' | ForEach-Object { Get-SwiftOmniUIPackage $_ }

    foreach ($component in $components) {
        $native = Join-Path $component "runtimes-framework\win-$Architecture\native"
        # NuGet DLL timestamps are not release ordering. Replace equal/older
        # timestamps too, or an incremental 1.8 -> 2.x build can mix runtimes.
        robocopy $native $Directory /E /IS /IT /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "the Windows App SDK could not be copied from $native" }
    }
    # What a backend's engine needs beside an application linking it, each backend lays itself.
    foreach ($backend in Get-ChildItem (Join-Path $SwiftOmniUIRepository 'lib\Backends') -Directory -Filter '*.WinUI') {
        $lays = Join-Path $backend.FullName 'SelfContained.ps1'
        if (Test-Path $lays) {
            $linked = $Backends -contains ('SwiftOmniUI' + $backend.Name.Replace('.', ''))
            & $lays -Directory $Directory -Architecture $Architecture -Linked $linked
        }
    }
    if ($Architecture -ne $SwiftOmniUIArchitecture) { Add-SwiftOmniUISwiftRuntime -Directory $Directory -Architecture $Architecture }
    $global:LASTEXITCODE = 0

    $manifest = New-SwiftOmniUIManifest $components
    foreach ($executable in $Executables) { [IO.File]::WriteAllText("$executable.manifest", $manifest) }

    # WinUI's controls find their resources in the application's index.
    Copy-Item (Join-Path $Directory 'Microsoft.UI.Xaml.Controls.pri') (Join-Path $Directory 'resources.pri') -Force
}

# The Swift runtime for `Architecture`, laid in `Directory`: the toolchain's
# own runtime stands on PATH, another architecture's nowhere. The Swift
# installer keeps each one as a merge module in its Redistributables - its
# File table and its cabinet, read through msi.dll and unpacked by expand.exe.
# Unpacked again only where the module differs from the one laid there.
# Design: docs/design/platforms/winui/runtime.md#another-architecture
function Add-SwiftOmniUISwiftRuntime([string]$Directory, [string]$Architecture) {
    $toolchain = Split-Path (Split-Path (Split-Path (Get-Command swift).Source))
    $swift = Split-Path (Split-Path $toolchain)
    $version = (Split-Path $toolchain -Leaf) -replace '\+.*$', ''
    $module = Join-Path $swift "Redistributables\$version\rtl.shared.$(@{ x64 = 'amd64'; arm64 = 'arm64' }[$Architecture]).msm"
    if (-not (Test-Path $module)) { throw "no Swift runtime for ${Architecture}: $module is missing" }
    $stamp = Join-Path $Directory 'swift-runtime.txt'
    $laid = "$module $((Get-Item $module).LastWriteTimeUtc.Ticks)"
    if ((Test-Path $stamp) -and (Get-Content $stamp -Raw).Trim() -eq $laid) { return }

    Write-Host "laying the Swift runtime for $Architecture"
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class SwiftOmniUIMergeModule {
    [DllImport("msi.dll", CharSet = CharSet.Unicode)] static extern uint MsiOpenDatabaseW(string path, IntPtr persist, out IntPtr database);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)] static extern uint MsiDatabaseOpenViewW(IntPtr database, string query, out IntPtr view);
    [DllImport("msi.dll")] static extern uint MsiViewExecute(IntPtr view, IntPtr record);
    [DllImport("msi.dll")] static extern uint MsiViewFetch(IntPtr view, out IntPtr record);
    [DllImport("msi.dll", CharSet = CharSet.Unicode)] static extern uint MsiRecordGetStringW(IntPtr record, uint field, StringBuilder value, ref uint size);
    [DllImport("msi.dll")] static extern uint MsiRecordReadStream(IntPtr record, uint field, byte[] buffer, ref uint size);
    [DllImport("msi.dll")] static extern uint MsiCloseHandle(IntPtr handle);

    static List<IntPtr> Rows(IntPtr database, string query) {
        IntPtr view, record;
        if (MsiDatabaseOpenViewW(database, query, out view) != 0) throw new Exception("cannot read " + query);
        MsiViewExecute(view, IntPtr.Zero);
        var rows = new List<IntPtr>();
        while (MsiViewFetch(view, out record) == 0) rows.Add(record);
        MsiCloseHandle(view);
        return rows;
    }

    // Each file's key in the module's cabinet, to its name.
    public static Dictionary<string, string> Files(string module) {
        IntPtr database;
        if (MsiOpenDatabaseW(module, IntPtr.Zero, out database) != 0) throw new Exception("cannot open " + module);
        var files = new Dictionary<string, string>();
        foreach (var row in Rows(database, "SELECT `File`, `FileName` FROM `File`")) {
            var key = new StringBuilder(1024); var name = new StringBuilder(1024); uint size = 1024;
            MsiRecordGetStringW(row, 1, key, ref size); size = 1024;
            MsiRecordGetStringW(row, 2, name, ref size);
            var bar = name.ToString().IndexOf('|');
            files[key.ToString()] = bar < 0 ? name.ToString() : name.ToString().Substring(bar + 1);
            MsiCloseHandle(row);
        }
        MsiCloseHandle(database);
        return files;
    }

    // The module's cabinet, written to `output`.
    public static void Cabinet(string module, string output) {
        IntPtr database;
        if (MsiOpenDatabaseW(module, IntPtr.Zero, out database) != 0) throw new Exception("cannot open " + module);
        using (var file = File.Create(output)) {
            foreach (var row in Rows(database, "SELECT `Data` FROM `_Streams` WHERE `Name` = 'MergeModule.CABinet'")) {
                var buffer = new byte[1 << 20]; uint size;
                do { size = (uint)buffer.Length; MsiRecordReadStream(row, 1, buffer, ref size); file.Write(buffer, 0, (int)size); } while (size > 0);
                MsiCloseHandle(row);
            }
        }
        MsiCloseHandle(database);
    }
}
'@ -ErrorAction SilentlyContinue

    $unpacked = Join-Path $env:TEMP "swiftomniui-swift-runtime-$Architecture-$PID"
    New-Item -ItemType Directory -Force $unpacked | Out-Null
    $cabinet = Join-Path $unpacked 'runtime.cab'
    [SwiftOmniUIMergeModule]::Cabinet($module, $cabinet)
    expand.exe $cabinet -F:* $unpacked | Out-Null
    if ($LASTEXITCODE) { throw "the Swift runtime for $Architecture could not be unpacked from $module" }
    $names = [SwiftOmniUIMergeModule]::Files($module)
    foreach ($each in Get-ChildItem $unpacked -Exclude 'runtime.cab') {
        # plutil is a tool of Foundation's, no part of what a program runs with.
        if ($names[$each.Name] -and $names[$each.Name] -ne 'plutil.exe') {
            Copy-Item $each.FullName (Join-Path $Directory $names[$each.Name]) -Force
        }
    }
    Remove-Item $unpacked -Recurse -Force
    Set-Content -Path $stamp -Value $laid -Encoding ascii
}

# The manifest a self-contained application carries: every class each
# component's package.appxfragment declares, in the file that holds it, and
# the application's own settings.
function New-SwiftOmniUIManifest([string[]]$Components) {
    $text = [System.Text.StringBuilder]::new()
    [void]$text.AppendLine("<?xml version='1.0' encoding='utf-8' standalone='yes'?>")
    [void]$text.AppendLine("<assembly manifestVersion='1.0' xmlns='urn:schemas-microsoft-com:asm.v1' xmlns:asmv3='urn:schemas-microsoft-com:asm.v3' xmlns:winrtv1='urn:schemas-microsoft-com:winrt.v1'>")
    foreach ($component in $Components) {
        [xml]$fragment = Get-Content (Join-Path $component 'runtimes-framework\package.appxfragment') -Raw
        $names = [System.Xml.XmlNamespaceManager]::new($fragment.NameTable)
        $names.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
        foreach ($server in $fragment.SelectNodes('./m:Fragment/m:Extensions/m:Extension/m:InProcessServer', $names)) {
            [void]$text.AppendLine("  <asmv3:file name='$($server.Path)'>")
            foreach ($class in $server.SelectNodes('./m:ActivatableClass', $names)) {
                [void]$text.AppendLine("    <winrtv1:activatableClass name='$($class.ActivatableClassId)' threadingModel='both'/>")
            }
            [void]$text.AppendLine('  </asmv3:file>')
        }
        foreach ($stub in $fragment.SelectNodes('./m:Fragment/m:Extensions/m:Extension/m:ProxyStub', $names)) {
            # A self-contained application has no singleton for these two.
            if ($stub.Path -in 'PushNotificationsLongRunningTask.ProxyStub.dll', 'Microsoft.Windows.Widgets.dll') { continue }
            [void]$text.AppendLine("  <asmv3:file name='$($stub.Path)'>")
            [void]$text.AppendLine("    <asmv3:comClass clsid='{$($stub.ClassId)}'/>")
            foreach ($interface in $stub.SelectNodes('./m:Interface', $names)) {
                [void]$text.AppendLine("    <asmv3:comInterfaceProxyStub name='$($interface.Name)' iid='{$($interface.InterfaceId)}'/>")
            }
            [void]$text.AppendLine('  </asmv3:file>')
        }
    }
    [void]$text.AppendLine(@'
  <asmv3:application>
    <asmv3:windowsSettings>
      <dpiAwareness xmlns='http://schemas.microsoft.com/SMI/2016/WindowsSettings'>PerMonitorV2</dpiAwareness>
    </asmv3:windowsSettings>
  </asmv3:application>
  <compatibility xmlns='urn:schemas-microsoft-com:compatibility.v1'>
    <application>
      <supportedOS Id='{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}'/>
    </application>
  </compatibility>
</assembly>
'@)
    return $text.ToString()
}
