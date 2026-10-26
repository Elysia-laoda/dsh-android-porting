# DSH on Android —— 移植补丁与踩坑记录

把 DeepSeek Harness（DSH）运行时搬进 Android APK 时，在 **Android 15/16/17（API 35–37）** 上必然撞到的一组坑，
以及每个坑的最小改法。不是又一个「DSH 安卓 App」，而是给做同类移植的人省时间的**补丁集 + 实测数据**。

- 验证环境：Cuttlefish / **Android 17（API 37，x86_64）**，DSH 运行时 `0.2.1-rc.2`，Node **26.12.1**（Termux bionic 构建）
- 上游：<https://github.com/deepseek-ai/deepseek-harness>（MIT）
- 适用面：任何把 DSH（或类似「Node 运行时 + Web UI」的组合）塞进 APK 的做法

**上游讨论**：<https://github.com/deepseek-ai/deepseek-harness/discussions/11047>
（上游仓库关闭了 Issues，按 CONTRIBUTING 的指引发在 Discussions。）

## 补丁一览

| 补丁 | 症状 | 一句话根因 |
|---|---|---|
| `patches/require-builtin-js-shim.patch` | 启动即 `No usable native binding found for node-addon-require-builtin-android-x64` | 该包只有各平台预编译 `.node`，没有 android；但外部只用到「把 `internal/...` 交给 require」 |
| `patches/flock-android-callback.patch` | 会话一直「深度求索中」、永不返回（**不报错**） | `flock` 在不支持的平台抛错后，改成直接 return 会让拿锁的 Promise **永不 settle** |
| `patches/session-link-to-rename.patch` | 每轮对话`EACCES: permission denied, link '...session.v4.jsonl...tmp'` | Android 拒绝对 app data 做 `link(2)`；`rename` 同盘原子，语义等价 |
| `patches/ptc-child-ld-library-path.patch` | PTC 模式 `run_code` 报 `CANNOT LINK EXECUTABLE ... libz.so.1 not found` | 子进程环境被重建时把 `LD_LIBRARY_PATH` 的值清空了，而子进程要重新执行同一个原生 node |

另外四个属于「打包/宿主侧」，不是运行时源码补丁，见 `docs/`：

| 问题 | 症状 | 改法 |
|---|---|---|
| AGP 只打包 `*.so` | Node 启动 `library "libz.so.1" not found` | 构建后把带版本号的库注入 `lib/<abi>/` 并重签（`scripts/build-apk.ps1`） |
| 应用数据目录不能执行 | `EACCES ... busybox: error=13` | 可执行文件放 jniLibs（`apk_data_file` 可执行），符号链接放应用目录 |
| `window.open` 登录黑屏 | 点登录后整页变白/黑 | `setSupportMultipleWindows(true)` + `onCreateWindow` 建应用内弹窗，并拦 `about:blank` |
| 桌面版设置页在手机上被挤成竖排 | 标签一字一行、右侧截断 | 移动端 CSS：全屏单栏 + 顶栏页签 + `box-sizing` + 缩放 |

## 实测：权限能力矩阵

同一组命令在三种上下文里的结果（Android 17，同机同镜像）：

| 命令 | root | shell（Shizuku 能给的面） | app（普通应用运行时） |
|---|---|---|---|
| `id` | uid=0 | uid=2000 | u0_a123 |
| `ls /data/data` | ✅ | ❌ Permission denied | ❌ |
| `pm list packages` | ✅ | ✅ | ❌ |
| `ls /sdcard` | ✅ | ✅ | ❌ |
| `settings get secure android_id` | ✅ | ✅ | ❌ |
| `cat /proc/version` | ✅ | ✅ | ✅ |

结论：**Shizuku 给的是「设备管理面」，不是 root**；`/data/data` 进不去。

## 应用补丁

每份 patch 都在对应包的根目录执行（`-p1`，文件头是 `a/lib/...`）：

```bash
cd node_modules/node-addon-require-builtin   && git apply -p1 ../../patches/require-builtin-js-shim.patch
cd node_modules/@deepseek-ai/node-addon-system && git apply -p1 ../../../patches/flock-android-callback.patch
cd node_modules/@deepseek-ai/dsh-session-persistence-jsonl && git apply -p1 ../../../patches/session-link-to-rename.patch
cd node_modules/@deepseek-ai/dsh-ptc-runtime-node && git apply -p1 ../../../patches/ptc-child-ld-library-path.patch
```

| patch | 目标包 | 目标文件 |
|---|---|---|
| `require-builtin-js-shim` | `node-addon-require-builtin` | `lib/index.js`（整个文件替换） |
| `flock-android-callback` | `@deepseek-ai/node-addon-system` | `lib/flock.js` |
| `session-link-to-rename` | `@deepseek-ai/dsh-session-persistence-jsonl` | `lib/index.js` |
| `ptc-child-ld-library-path` | `@deepseek-ai/dsh-ptc-runtime-node` | `lib/index.js` |

四份都在对应的原始 npm 包上做过 `git apply --check`（2026-10-26）。

## 怎么用

1. 先按 `docs/01-runtime-patches.md` 把四个补丁打进 `node_modules`（每份 patch 都可 `git apply` 到对应包的原始文件）。
2. 按 `docs/02-native-payload.md` 把 Node 与共享库放进 APK。
3. 想要「应用内自带 shell」，见 `docs/03-userland-in-apk.md`（bash + busybox 作为 jniLibs）。
4. 界面与登录见 `docs/04-mobile-surfaces.md`。

脚本是 Windows + PowerShell 7 的，路径用参数传入；Linux 侧对应操作在文档里写明（`tar`/`7z`/`patchelf` 等价）。

## 已验证 / 未验证

已实测：四个运行时补丁、Node 与共享库装载、276 个 busybox applet、应用内登录弹窗、设置页移动版布局、
agent 真实对话（真 API，4 秒一轮）。

未实测：**arm64 真机**（补丁与打包流程与 ABI 无关，但只在 x86_64 模拟器上跑过）；
**Shizuku shell 身份执行**（代码在，模拟器上起不来 Shizuku 服务）；Windows/macOS 桌面宿主上的行为。

## 许可

本仓库的文档与脚本：MIT。补丁所改的上游包均为 MIT（`@deepseek-ai/*`、`node-addon-*`）。
若你像本项目一样把 **bash(GPLv3) / busybox(GPLv2)** 打进 APK 并分发，请自行处理 GPL 义务（附源码或书面要约）；
不打算分发就无所谓。

---

# DSH on Android — porting patches and field notes (English)

DeepSeek Harness (DSH) is a Node runtime plus a browser UI. Putting it inside an Android APK hits a
fixed set of Android 15/16/17 (API 35–37) walls. This repo is the patch set and the measurements, not
another "DSH Android app".

Environment: Cuttlefish / **Android 17 (API 37, x86_64)**, DSH runtime `0.2.1-rc.2`, Node **26.12.1**
(Termux bionic build). Upstream: <https://github.com/deepseek-ai/deepseek-harness> (MIT).

| Patch | Symptom | Root cause |
|---|---|---|
| `require-builtin-js-shim` | boot fails: `No usable native binding found for node-addon-require-builtin-android-x64` | no android prebuild exists; the package only needs `require("internal/...")` |
| `flock-android-callback` | conversation hangs in "thinking" forever, no error | replacing the thrown error with a bare return leaves the lock promise pending forever |
| `session-link-to-rename` | `EACCES ... link '...jsonl.zstd.*.tmp'` on every turn | Android denies `link(2)` inside app data; `rename` is atomic within one filesystem |
| `ptc-child-ld-library-path` | PTC `run_code` fails with `CANNOT LINK EXECUTABLE ... libz.so.1` | the child environment is rebuilt with every value cleared, including the loader path |

Host-side issues (packaging, not runtime source) are documented in `docs/`: AGP drops versioned `.so`
files; app data is not executable (W^X) so binaries live in jniLibs; `window.open` needs
`setSupportMultipleWindows` or the login flow blanks the page; the desktop settings dialog needs a
phone layout.

Verified: all four runtime patches, native payload loading, 276 busybox applets, in-app login popup,
mobile settings layout, a real agent turn against the live API (4 s).
Not verified: arm64 hardware, Shizuku shell execution (code present, Shizuku server would not start on
the emulator), desktop hosts.

License: docs and scripts MIT. Bundling **bash (GPLv3) / busybox (GPLv2)** into a distributed APK
carries GPL obligations — handle that if you ship it.