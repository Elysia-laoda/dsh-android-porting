# 二、把 Node 运行时放进 APK

## 资源从哪来

Android 上跑 Node 需要 **bionic** 构建（glibc 的 `node-vX-linux-x64.tar.xz` 跑不起来）。
最省事且可持续的来源是 Termux 的包（`packages.termux.dev`）：

```
nodejs 26.12.1  Depends: libc++, openssl, c-ares, libicu, libsqlite, zlib, libffi
```

把 `.deb` 解开（`ar` + `tar`，或 7-Zip）后需要：

| 用途 | 文件 |
|---|---|
| 可执行文件 | `data/data/com.termux/files/usr/bin/node` |
| 共享库 | `lib/` 下 `libc++_shared.so`、`libcares.so`、`libcrypto.so.3`、`libssl.so.3`、`libicudata/i18n/io/tu/uc.so.78`、`libsqlite3.so`、`libz.so.1`、`libffi.so` |
| CA bundle | `etc/tls/cert.pem` |

## 两个硬约束

### 1) 可执行文件必须在 nativeLibraryDir

targetSdk ≥ 29 的应用**不能 exec 应用数据目录里的文件**（`EACCES`，W^X）。所以：

- 把 `node` 改名成 `libnode_exec.so` 放进 `app/src/main/jniLibs/<abi>/`；
- manifest 里 `android:extractNativeLibs="true"` + Gradle `packaging.jniLibs.useLegacyPackaging = true`；
- 运行时 exec `<nativeLibraryDir>/libnode_exec.so`，并设 `LD_LIBRARY_PATH=<nativeLibraryDir>`。

`rename` 出来的是合法 ELF，只要可执行位在就能 execve —— 名字里带 `lib...so` 只是为了被 AGP 收进去。

### 2) AGP 只打包 `*.so`，带版本号的库会被静默丢掉

实测：`jniLibs` 里 13 个文件，APK 里只剩 5 个 —— `libz.so.1`、`libssl.so.3`、`libicu*.so.78`
这些**根本没有进包**，运行时表现为 `library "libz.so.1" not found`。

**改法**（构建脚本里做）：`assembleRelease` 之后把 `.so.` 形式的库注入 `lib/<abi>/` 再重置签名：

```powershell
7z a -tzip $apk 'lib\<abi>\*'
apksigner sign --ks <debug.keystore> --out signed.apk $apk
```

> `extractNativeLibs=true` 时安装器会把 `lib/<abi>/` 下**所有**文件解到 nativeLibraryDir（不要求 `.so` 后缀），
> 所以注入的名字可以保持 SONAME 原样（`libz.so.1`）。

## JS 载荷

`node_modules` 整棵树（`@deepseek-ai/*` 约 300 个包）压成 `assets/dsh-tree.zip`，
首次启动解到 `files/runtime/`（6–8 秒，6 万多个文件）。体积上可以把
`dsh-experimental-inspector`（devtools，22 MB）和 `node-pty/prebuilds` 排除掉。

## 启动参数

```
<node> --expose-internals --dns-result-order=ipv4first \
  <runtime>/node_modules/@deepseek-ai/dsh/lib/bin.js web --no-open --host 127.0.0.1 --port 0
```

环境：`DSH_HOME`、`HOME`、`TMPDIR`、`PATH`、`LD_LIBRARY_PATH`、`SSL_CERT_FILE`、`NODE_EXTRA_CA_CERTS`。
stdout 里出现 `dsh web: http://127.0.0.1:<port>/?token=...` 就是起来了，把这个 URL 交给 WebView。
