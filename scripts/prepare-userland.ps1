# NOTE (porting repo): 这些脚本来自一个可用的构建工程，默认路径指向作者机器（D:\dshproject\dsh-mobile-android）。
# 复用时把 -ProjectDir / -StageDir / -Index 指到你自己的工程与包索引即可。
# 依赖：PowerShell 7、7-Zip、JDK、Android SDK（build-tools 含 apksigner）、node（仅 prepare-* 用）。

#requires -Version 7.0
<#
.SYNOPSIS
Ship a tiny Termux userland (bash + busybox) as APK native libraries.
.DESCRIPTION
Android refuses to exec binaries stored in app data (W^X for targetSdk >= 29), so the shell has
to live in nativeLibraryDir like the node executable: bash -> libbash_exec.so, busybox ->
libbusybox_exec.so, and every shared library they need. The app then creates applet symlinks in
its own writable directory and points PATH there.
#>
param(
    [Parameter(Mandatory = $true)][string]$Abi,
    [Parameter(Mandatory = $true)][string]$Index,
    [string]$ProjectDir = 'D:\dshproject\dsh-mobile-android',
    [string]$WorkRoot = 'D:\dshproject\_tmp\userland'
)
$ErrorActionPreference = 'Stop'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$base = 'https://packages.termux.dev/apt/termux-main/'
$packages = @('bash', 'busybox', 'libandroid-support', 'libandroid-selinux', 'pcre2', 'libiconv', 'readline', 'ncurses')

$work = Join-Path $WorkRoot $Abi
$debDir = Join-Path $work 'deb'
$root = Join-Path $work 'root'
New-Item -ItemType Directory -Force -Path $debDir, $root | Out-Null

Write-Host '[1/3] download'
$rows = & node 'D:\dshproject\_tmp\pkg-files.mjs' $Index @packages
foreach ($row in $rows) {
    $parts = $row.Split([char]9)
    if ($parts.Count -lt 2 -or $parts[1] -eq 'MISSING') { throw ('package not found: ' + $parts[0]) }
    $file = Split-Path $parts[1] -Leaf
    $out = Join-Path $debDir $file
    if (Test-Path $out) { continue }
    Invoke-WebRequest -Uri ($base + ($parts[1] -replace ':', '%3A')) -OutFile $out -TimeoutSec 240 -UseBasicParsing
}

Write-Host '[2/3] extract'
foreach ($deb in Get-ChildItem $debDir -Filter *.deb) {
    $tmp = Join-Path $work ('x-' + $deb.BaseName)
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    & $sevenZip x $deb.FullName ('-o' + $tmp) -y | Out-Null
    $xz = Join-Path $tmp 'data.tar.xz'
    if (-not (Test-Path $xz)) { continue }
    & $sevenZip x $xz ('-o' + $tmp) -y | Out-Null
    & $sevenZip x (Join-Path $tmp 'data.tar') ('-o' + $root) -y | Out-Null
}

$usr = Join-Path $root 'data\data\com.termux\files\usr'
$jni = Join-Path $ProjectDir ('app\src\main\jniLibs\' + $Abi)
New-Item -ItemType Directory -Force -Path $jni | Out-Null

Write-Host '[3/3] stage into jniLibs'
Copy-Item (Join-Path $usr 'bin\bash') (Join-Path $jni 'libbash_exec.so') -Force
Copy-Item (Join-Path $usr 'bin\busybox') (Join-Path $jni 'libbusybox_exec.so') -Force

$libSrc = Join-Path $usr 'lib'
$realLibs = @(Get-ChildItem $libSrc -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 -and $_.Name -match '\.so' })
foreach ($item in $realLibs) {
    Copy-Item $item.FullName (Join-Path $jni $item.Name) -Force
    if ($item.Name -match '^(.+?\.so)(\.\d+)(\..+)?$') {
        Copy-Item $item.FullName (Join-Path $jni ($Matches[1] + $Matches[2])) -Force
        Copy-Item $item.FullName (Join-Path $jni $Matches[1]) -Force
    }
}

'bins: ' + (Test-Path (Join-Path $jni 'libbash_exec.so')) + ' / ' + (Test-Path (Join-Path $jni 'libbusybox_exec.so'))
'jniLibs files: ' + ((Get-ChildItem $jni).Count)
'jniLibs MB: ' + [math]::Round(((Get-ChildItem $jni | Measure-Object Length -Sum).Sum / 1MB), 2)
