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
# Builds an application's WinUI head, lays the Windows App SDK beside it and
# starts it.
#
#   .\run-app.ps1 -App apps\HelloWorld [-Configuration debug|release] [-Architecture arm64|x64] [-Detach | -BuildOnly]
#
#   -App           the application's folder: Package.swift, and Platforms\WinUI
#   -Architecture  what the head is built for: this machine's own by default;
#                  an ARM64 machine builds x64 too, which Windows runs emulated
#   -Detach        returns once the application has started, instead of waiting
#                  for it and passing on what it writes
#   -BuildOnly     starts nothing: the head stands ready for a debugger to start
#
# Everything a build writes stays under <App>\.build\winui, each architecture's
# head in a folder of its own (--show-bin-path).
# ---------------------------------------------------------------------------
param(
    [Parameter(Mandatory = $true)][string]$App,
    [ValidateSet('debug', 'release')][string]$Configuration = 'debug',
    [ValidateSet('arm64', 'x64')][string]$Architecture,
    [switch]$Detach,
    [switch]$BuildOnly
)
. (Join-Path $PSScriptRoot 'tools.ps1')
if (-not $Architecture) { $Architecture = $SwiftOmniUIArchitecture }
$arch = Get-SwiftOmniUIArchitectureArguments $Architecture

$application = (Resolve-Path $App).Path
$name = Split-Path $application -Leaf
$scratch = Join-Path $application '.build\winui'

# A running head holds its executable, which the build writes again: it stops first.
$running = Get-Process -Name "${name}WinUI" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "stopping the ${name}WinUI that runs"
    $running | Stop-Process -Force
}
$global:LASTEXITCODE = 0

Initialize-SwiftOmniUIProjection
$env:SWIFTOMNIUI_HOST = 'winui'

# SwiftTerm's build-info plugin asks git, and Foundation's process spawn dies in
# sessions that cannot raise CFSocket's wakeup pair (VS Code tasks, SSH). Answer
# for it: set values in the caller's environment to give real ones.
if (-not $env:SWIFTTERM_BUILD_BRANCH) { $env:SWIFTTERM_BUILD_BRANCH = 'main' }
if (-not $env:SWIFTTERM_BUILD_TAG) { $env:SWIFTTERM_BUILD_TAG = 'none' }
if (-not $env:SWIFTTERM_BUILD_COMMIT) { $env:SWIFTTERM_BUILD_COMMIT = 'unknown' }
if (-not $env:SWIFTTERM_BUILD_DIRTY) { $env:SWIFTTERM_BUILD_DIRTY = '0' }

Write-Host "building ${name}WinUI, $Configuration, $Architecture - SwiftPM reads the packages first, printing nothing"
Write-SwiftOmniUIEditorBuilds
swift build --package-path $application -c $Configuration --product "${name}WinUI" --scratch-path $scratch @arch
if ($LASTEXITCODE) { throw "the WinUI head of $name did not build" }
Write-Host "laying the Windows App SDK beside ${name}WinUI.exe"
$bin = (swift build --package-path $application -c $Configuration --scratch-path $scratch --show-bin-path @arch).Trim()
$executable = Join-Path $bin "${name}WinUI.exe"
$backends = @(Get-SwiftOmniUILinkedBackends -Package $application -Product "${name}WinUI")
Set-SwiftOmniUISelfContained -Directory $bin -Executables $executable -Architecture $Architecture -Backends $backends

# The application's pictures stand beside it, where its WinUI host reads them.
# They live at Resources\Images, or - a library holding its own assets - Sources\<target>\Assets\Images.
$images = Join-Path $application 'Resources\Images'
if (-not (Test-Path $images)) {
    $candidate = Get-ChildItem -Path (Join-Path $application 'Sources') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'Assets\Images' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if ($candidate) { $images = $candidate }
}
if (Test-Path $images) {
    Copy-Item -Path (Join-Path $images '*') -Destination (New-Item -ItemType Directory -Force (Join-Path $bin 'Images')) -Recurse -Force
}

# Bundle resources - the directories and loose files `Bundle.main` answers for.
$bundleResources = Join-Path $application 'Resources\Bundle'
if (-not (Test-Path $bundleResources)) {
    $candidate = Get-ChildItem -Path (Join-Path $application 'Sources') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'Assets\Bundle' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if ($candidate) { $bundleResources = $candidate }
}
if (Test-Path $bundleResources) {
    Copy-Item -Path (Join-Path $bundleResources '*') -Destination $bin -Recurse -Force
}

if ($BuildOnly) {
    Write-Host "built $executable"
    exit 0
}

Write-Host "starting $executable"
if ($Detach) {
    $process = Start-Process -FilePath $executable -WorkingDirectory $bin -PassThru
    Write-Host "process $($process.Id)"
} else {
    # A windowed application: the script waits for it, and what it writes comes out here.
    $process = Start-Process -FilePath $executable -NoNewWindow -Wait -PassThru
    exit $process.ExitCode
}
