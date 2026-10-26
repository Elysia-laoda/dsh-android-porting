# NOTE (porting repo): 这些脚本来自一个可用的构建工程，默认路径指向作者机器（D:\dshproject\dsh-mobile-android）。
# 复用时把 -ProjectDir / -StageDir / -Index 指到你自己的工程与包索引即可。
# 依赖：PowerShell 7、7-Zip、JDK、Android SDK（build-tools 含 apksigner）、node（仅 prepare-* 用）。

#requires -Version 7.0
<#
.SYNOPSIS
Rebuild the runtime payload that ships inside the APK (assets zip only; the APK itself is build-apk.ps1).
.DESCRIPTION
1. npm install @deepseek-ai/dsh for an android/x64 target (scripts disabled, platform packages skipped)
2. patch node-addon-require-builtin with the pure-JS implementation
3. copy the Termux CA bundle next to the tree
4. stage the tree (dropping unusable native prebuilds and the devtools inspector) and zip it
#>
param(
    [string]$WorkDir = 'D:\dshproject\_tmp\mobile-dsh',
    [string]$StageDir = 'D:\dshproject\_tmp\asset-stage',
    [string]$CaBundle = 'D:\dshproject\_tmp\termuxroot\data\data\com.termux\files\usr\etc\tls\cert.pem',
    [string]$DshVersion = '0.2.1-rc.2'
)
$ErrorActionPreference = 'Stop'

Write-Host '[1/4] npm install'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
Set-Content -LiteralPath (Join-Path $WorkDir 'package.json') -Value '{ "name": "dsh-mobile", "private": true, "version": "0.0.0", "type": "module" }' -Encoding utf8NoBOM
Push-Location $WorkDir
try {
    npm install "@deepseek-ai/dsh@$DshVersion" --os=android --cpu=x64 --ignore-scripts --omit=dev --no-audit --no-fund
} finally { Pop-Location }

Write-Host '[2/4] patch node-addon-require-builtin'
$shim = @'
"use strict";
// Android port: the upstream package only ships prebuilt native bindings, none for android-x64.
// It exposes one capability -- require() of Node internal module ids -- which plain require
// provides when Node runs with --expose-internals.
function requireBuiltin(moduleId) { return require(moduleId); }
function isAllowedInternalId(moduleId) {
  if (typeof moduleId !== 'string' || moduleId.length === 0) return false;
  try { require.resolve(moduleId); return true; } catch { return false; }
}
function getBindingInfo() {
  return { backend: 'js-expose-internals', platform: process.platform, arch: process.arch,
           versions: { node: process.version, napi: process.versions.napi } };
}
module.exports = { requireBuiltin, isAllowedInternalId, getBindingInfo,
                   default: { requireBuiltin, isAllowedInternalId, getBindingInfo } };
'@
$target = Join-Path $WorkDir 'node_modules\node-addon-require-builtin\lib\index.js'
[IO.File]::WriteAllText($target, $shim, (New-Object System.Text.UTF8Encoding($false)))

Write-Host '[3/4] stage tree'
$null = robocopy $WorkDir $StageDir /E /XD (Join-Path $WorkDir 'node_modules\node-pty\prebuilds') (Join-Path $WorkDir 'node_modules\@deepseek-ai\dsh-experimental-inspector') /NFL /NDL /NJH /NJS /NP
New-Item -ItemType Directory -Force -Path (Join-Path $StageDir 'ca') | Out-Null
Copy-Item $CaBundle (Join-Path $StageDir 'ca\cert.pem') -Force

Write-Host '[4/4] done'
Get-ChildItem $StageDir | Select-Object Name
