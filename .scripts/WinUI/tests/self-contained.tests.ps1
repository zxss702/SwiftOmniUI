# SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
# SPDX-License-Identifier: Apache-2.0

# Deployment regression fixtures only: no compiler, package downloads or app
# launch. Run separately from the native suites when verification is allowed.
. (Join-Path $PSScriptRoot '..\tools.ps1')
$ErrorActionPreference = 'Stop'

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('soui-sdk-deployment-' + [guid]::NewGuid())
$packageFolders = @{}

function Assert-File([string]$Path, [string]$Expected) {
    if (-not (Test-Path $Path) -or [IO.File]::ReadAllText($Path) -ne $Expected) {
        throw "wrong deployed contents: $Path"
    }
}

function Get-SwiftOmniUIPackage([string]$Id) {
    if (-not $packageFolders.ContainsKey($Id)) { throw "unexpected package: $Id" }
    return $packageFolders[$Id]
}

try {
    # Keep backend selection real, with the production deployment entry point,
    # but replace package acquisition by local, non-executable fixture files.
    $components = @{
        'microsoft.windowsappsdk.winui' = @('Microsoft.UI.Xaml.dll', 'Microsoft.UI.Xaml.Settings.XamlOptionalChanges')
        'microsoft.windowsappsdk.foundation' = @('Microsoft.WindowsAppRuntime.dll', 'Microsoft.Windows.ApplicationModel.WindowsAppRuntime.RuntimeCompatibilityOptions')
        'microsoft.windowsappsdk.interactiveexperiences' = @('Microsoft.UI.Composition.dll', 'Microsoft.UI.Composition.Compositor')
    }
    foreach ($id in $components.Keys) {
        $folder = Join-Path $fixture "packages\$id"
        $packageFolders[$id] = $folder
        $dll, $class = $components[$id]
        foreach ($architecture in @('x64', 'arm64')) {
            $native = Join-Path $folder "runtimes-framework\win-$architecture\native"
            New-Item -ItemType Directory -Force $native | Out-Null
            $file = Join-Path $native $dll
            [IO.File]::WriteAllText($file, "$id $architecture new")
            (Get-Item $file).LastWriteTimeUtc = [datetime]'2001-01-01'
            if ($id -eq 'microsoft.windowsappsdk.winui') {
                [IO.File]::WriteAllText((Join-Path $native 'Microsoft.UI.Xaml.Controls.pri'), "resources $architecture new")
            }
        }
        [IO.File]::WriteAllText((Join-Path $folder 'runtimes-framework\package.appxfragment'), @"
<Fragment xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Extensions><Extension><InProcessServer><Path>$dll</Path>
    <ActivatableClass ActivatableClassId="$class" ThreadingModel="both"/>
  </InProcessServer></Extension></Extensions>
</Fragment>
"@)
    }
    $webview = Join-Path $fixture 'packages\webview'
    $packageFolders['microsoft.web.webview2'] = $webview
    foreach ($architecture in @('x64', 'arm64')) {
        foreach ($kind in @('native', 'native_uap')) {
            New-Item -ItemType Directory -Force (Join-Path $webview "runtimes\win-$architecture\$kind") | Out-Null
        }
        [IO.File]::WriteAllText((Join-Path $webview "runtimes\win-$architecture\native_uap\Microsoft.Web.WebView2.Core.dll"), "webview $architecture new")
        [IO.File]::WriteAllText((Join-Path $webview "runtimes\win-$architecture\native\WebView2Loader.dll"), "loader $architecture new")
    }

    foreach ($architecture in @('x64', 'arm64')) {
        # Avoid consulting a Swift installation: test each payload as the
        # machine's native architecture, with architecture-specific fixtures.
        $SwiftOmniUIArchitecture = $architecture
        foreach ($withWebView in @($false, $true)) {
            $output = Join-Path $fixture "output-$architecture-$withWebView"
            New-Item -ItemType Directory -Force $output | Out-Null
            foreach ($component in $components.Values) {
                $old = Join-Path $output $component[0]
                [IO.File]::WriteAllText($old, 'old runtime with a newer timestamp')
                (Get-Item $old).LastWriteTimeUtc = [datetime]'2026-10-01'
            }
            $executable = Join-Path $output 'fixture.exe'
            $backends = if ($withWebView) { @('SwiftOmniUIWebViewWinUI') } else { @() }
            Set-SwiftOmniUISelfContained -Directory $output -Executables @($executable) `
                -Architecture $architecture -Backends $backends

            foreach ($id in $components.Keys) {
                Assert-File (Join-Path $output $components[$id][0]) "$id $architecture new"
            }
            Assert-File (Join-Path $output 'resources.pri') "resources $architecture new"
            [xml]$manifest = Get-Content "$executable.manifest" -Raw
            foreach ($component in $components.Values) {
                if (-not $manifest.OuterXml.Contains($component[1])) { throw "missing native class $($component[1])" }
            }
            if ($withWebView) {
                Assert-File (Join-Path $output 'Microsoft.Web.WebView2.Core.dll') "webview $architecture new"
                Assert-File (Join-Path $output 'WebView2Loader.dll') "loader $architecture new"
            } elseif ((Test-Path (Join-Path $output 'Microsoft.Web.WebView2.Core.dll')) -or
                      (Test-Path (Join-Path $output 'WebView2Loader.dll'))) {
                throw 'a non-WebView application acquired WebView deployment files'
            }
        }
    }
} finally {
    if (Test-Path $fixture) { Remove-Item -Recurse -Force $fixture }
}
