# SPDX-License-Identifier: Apache-2.0
# Compile an application icon as a link input, never rewrite the finished exe.
# Resources/AppIcon/appicon.ico is preferred; appicon.png is converted with the
# Windows imaging APIs. This script is dot-sourced; defining it runs no tools.
function Get-SwiftOmniUIAppDisplayName([string]$Application) {
    $metadata = Join-Path $Application 'Resources\Bundle\app-info.json'
    if (-not (Test-Path $metadata)) {
        $metadata = Get-ChildItem (Join-Path $Application 'Sources') -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName 'Assets\Bundle\app-info.json' } |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($metadata) {
        $info = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($info.displayName -is [string] -and -not [string]::IsNullOrWhiteSpace($info.displayName) -and
            $info.displayName -notmatch '[\r\n]') { return [string]$info.displayName }
        throw 'app-info.json must supply a nonempty single-line displayName.'
    }
    return Split-Path $Application -Leaf
}

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
    $displayName = (Get-SwiftOmniUIAppDisplayName $Application).Replace('\', '\\').Replace('"', '\"')
    $rc = Join-Path $output 'appicon.rc'
    # SwiftPM does not track an arbitrary linker's resource input. Include its
    # content identity in the argument so changing the artwork forces relinking.
    $identity = (Get-FileHash -LiteralPath $icon -Algorithm SHA256 -ErrorAction Stop).Hash
    $description = @"
1 ICON "$escaped"
1 VERSIONINFO
 FILEVERSION 0,0,0,0
 PRODUCTVERSION 0,0,0,0
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904B0"
  BEGIN
   VALUE "FileDescription", "$displayName\0"
   VALUE "ProductName", "$displayName\0"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1200
 END
END
"@
    [IO.File]::WriteAllText($rc, $description, [Text.Encoding]::Unicode)
    $metadataIdentity = (Get-FileHash -LiteralPath $rc -Algorithm SHA256 -ErrorAction Stop).Hash
    $resource = Join-Path $output "appicon-$identity-$metadataIdentity.res"
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
function Set-SwiftOmniUIAppLauncher([string]$Executable, [string]$Name, [string]$Application) {
    $displayName = if ($Application) { Get-SwiftOmniUIAppDisplayName $Application } else { $Name }
    if ($displayName.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
        throw 'The application displayName cannot be used as a Start-menu shortcut filename.'
    }
    $programs = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
    if (-not $programs) { throw 'The current user has no Start-menu Programs directory.' }
    New-Item -ItemType Directory -Force $programs -ErrorAction Stop | Out-Null
    $shell = New-Object -ComObject WScript.Shell -ErrorAction Stop
    try {
        $shortcut = $shell.CreateShortcut((Join-Path $programs "$displayName.lnk"))
        try {
            $shortcut.TargetPath = $Executable
            $shortcut.WorkingDirectory = Split-Path $Executable
            $shortcut.IconLocation = "$Executable,0"
            $shortcut.Description = $displayName
            $shortcut.Save()
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
        # Migrate only our old executable-named shortcut, never an unrelated one.
        $oldPath = Join-Path $programs "$Name.lnk"
        if ($displayName -ne $Name -and (Test-Path $oldPath)) {
            $old = $shell.CreateShortcut($oldPath)
            try {
                if ($old.TargetPath -eq $Executable) { Remove-Item -LiteralPath $oldPath -ErrorAction Stop }
            } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($old) }
        }
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}
