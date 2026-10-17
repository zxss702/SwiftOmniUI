# SPDX-License-Identifier: Apache-2.0
# Compile an application icon as a link input, never rewrite the finished exe.
# Resources/AppIcon/appicon.ico is preferred; appicon.png is converted with the
# Windows imaging APIs. This script is dot-sourced; defining it runs no tools.
function Get-SwiftOmniUIAppIconResource([string]$Application, [string]$Scratch, [string]$Architecture) {
    $assets = Join-Path $Application 'Resources\AppIcon'
    $icon = Join-Path $assets 'appicon.ico'
    $png = Join-Path $assets 'appicon.png'
    if (-not (Test-Path $icon) -and -not (Test-Path $png)) { return $null }
    $output = Join-Path $Scratch "app-icon\$Architecture"
    New-Item -ItemType Directory -Force $output -ErrorAction Stop | Out-Null
    if (-not (Test-Path $icon)) {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $icon = Join-Path $output 'appicon.ico'
        $source = [Drawing.Image]::FromFile($png)
        try {
            $frames = @()
            foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
                $bitmap = [Drawing.Bitmap]::new($size, $size)
                $graphics = [Drawing.Graphics]::FromImage($bitmap)
                $stream = [IO.MemoryStream]::new()
                try {
                    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.DrawImage($source, 0, 0, $size, $size)
                    $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
                    $frames += ,([pscustomobject]@{ Size = $size; Bytes = $stream.ToArray() })
                } finally { $stream.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
            }
            $writer = [IO.BinaryWriter]::new([IO.File]::Create($icon))
            try {
                $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
                $offset = 6 + 16 * $frames.Count
                foreach ($frame in $frames) {
                    $dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
                    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
                    $writer.Write([byte]0); $writer.Write([byte]0)
                    $writer.Write([uint16]1); $writer.Write([uint16]32)
                    $writer.Write([uint32]$frame.Bytes.Length); $writer.Write([uint32]$offset)
                    $offset += $frame.Bytes.Length
                }
                foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
            } finally { $writer.Dispose() }
        } finally { $source.Dispose() }
    }
    # Resource files use C-style escaping, including in absolute Windows paths.
    $escaped = $icon.Replace('\', '\\').Replace('"', '\"')
    $rc = Join-Path $output 'appicon.rc'
    # SwiftPM does not track an arbitrary linker's resource input. Include its
    # content identity in the argument so changing the artwork forces relinking.
    $identity = (Get-FileHash -LiteralPath $icon -Algorithm SHA256 -ErrorAction Stop).Hash
    $resource = Join-Path $output "appicon-$identity.res"
    [IO.File]::WriteAllText($rc, "1 ICON `"$escaped`"`r`n", [Text.Encoding]::Unicode)
    $compiler = Get-Command rc.exe -ErrorAction SilentlyContinue
    if (-not $compiler) {
        $sdk = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
        $toolArchitecture = if ($SwiftOmniUIArchitecture -eq 'arm64') { 'arm64' } else { 'x64' }
        $compiler = Get-ChildItem $sdk -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName "$toolArchitecture\rc.exe" } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    } else { $compiler = $compiler.Source }
    if (-not $compiler) { throw 'Application icons require the Windows SDK resource compiler (rc.exe).' }
    & $compiler /nologo /fo $resource $rc | Out-Host
    if ($LASTEXITCODE) { throw 'The application icon resource could not be compiled.' }
    return $resource
}

# An unpackaged desktop application uses a normal per-user Start-menu shortcut.
# Point it at the current run/deploy output; IconLocation reads the exe resource.
function Set-SwiftOmniUIAppLauncher([string]$Executable, [string]$Name) {
    $programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    if (-not $programs) { throw 'The current user has no Start-menu Programs directory.' }
    New-Item -ItemType Directory -Force $programs -ErrorAction Stop | Out-Null
    $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
    try {
        $shortcut = $shell.CreateShortcut((Join-Path $programs "$Name.lnk"))
        try {
            $shortcut.TargetPath = $Executable
            $shortcut.WorkingDirectory = Split-Path $Executable
            $shortcut.IconLocation = "$Executable,0"
            $shortcut.Description = $Name
            $shortcut.Save()
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}
