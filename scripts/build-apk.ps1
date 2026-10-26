# NOTE (porting repo): 这些脚本来自一个可用的构建工程，默认路径指向作者机器（D:\dshproject\dsh-mobile-android）。
# 复用时把 -ProjectDir / -StageDir / -Index 指到你自己的工程与包索引即可。
# 依赖：PowerShell 7、7-Zip、JDK、Android SDK（build-tools 含 apksigner）、node（仅 prepare-* 用）。

#requires -Version 7.0
<#
.SYNOPSIS
Build the DSH Mobile APK: assets zip, Gradle release build, native-library injection, signing.
.DESCRIPTION
AGP only packages files matching *.so from jniLibs, so the versioned shared libraries
(libz.so.1, libicu*.so.78, libssl.so.3, ...) are injected into lib/<abi>/ after packaging and
the APK is re-signed.
#>
param(
    [string]$ProjectDir = 'D:\dshproject\dsh-mobile-android',
    [string]$StageDir = 'D:\dshproject\_tmp\asset-stage',
    [string]$OutputDir = 'D:\dshproject\dsh-mobile-android\dist',
    [switch]$SkipAssets
)
$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'D:\Java'
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$apksigner = 'D:\Android\sdk\build-tools\36.0.0\apksigner.bat'
$debugKeystore = Join-Path $env:USERPROFILE '.android\debug.keystore'

if (-not $SkipAssets) {
    Write-Host '[1/5] zip runtime assets'
    $zipPath = Join-Path $ProjectDir 'app\src\main\assets\dsh-tree.zip'
    New-Item -ItemType Directory -Force -Path (Split-Path $zipPath) | Out-Null
    if (Test-Path $zipPath) { [IO.File]::Delete($zipPath) }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($StageDir, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
    Write-Host ('      ' + [math]::Round((Get-Item $zipPath).Length / 1MB, 1) + ' MB')
}

Write-Host '[2/5] gradle assembleRelease'
Push-Location $ProjectDir
try { & .\gradlew.bat assembleRelease --no-daemon -q } finally { Pop-Location }

$apk = Join-Path $ProjectDir 'app\build\outputs\apk\release\app-release.apk'
if (-not (Test-Path $apk)) { throw "missing $apk" }

Write-Host '[3/5] inject versioned native libraries'
$jni = Join-Path $ProjectDir 'app\src\main\jniLibs'
$versioned = Get-ChildItem $jni -Recurse -File | Where-Object { $_.Name -match '\.so\.\d' }
if ($versioned.Count -eq 0) { throw 'no versioned libraries found in jniLibs' }
$staging = Join-Path $env:TEMP 'dsh-mobile-libs'
if (Test-Path $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
foreach ($f in $versioned) {
    $target = Join-Path $staging ('lib\' + $f.Directory.Name)
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    Copy-Item $f.FullName $target -Force
}
Push-Location $staging
try { & $sevenZip a -tzip $apk 'lib\*' -r | Select-Object -Last 1 } finally { Pop-Location }

Write-Host '[4/5] sign'
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$signed = Join-Path $OutputDir 'dsh-mobile-release.apk'
if (Test-Path $signed) { [IO.File]::Delete($signed) }
& $apksigner sign --ks $debugKeystore --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out $signed $apk

Write-Host '[5/5] done'
Get-Item $signed | ForEach-Object { $_.FullName + '  ' + [math]::Round($_.Length / 1MB, 1) + ' MB' }
