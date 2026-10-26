# 一、四个运行时补丁

每个补丁都能直接 `git apply`（或 `patch -p1`）到对应包的原始文件。
上下文来自 `@deepseek-ai` 运行时 `0.2.1-rc.2`；换版本后行号会变，但定位行一眼能认出。

## 1. `node-addon-require-builtin` —— 换成纯 JS

**症状**（启动即死）：

```
dsh: host preparation failed: No usable native binding found for node-addon-require-builtin-android-x64 (auto)
  cause: Cannot find module 'node-addon-require-builtin-android-x64'
```

**为什么**：这个包只发布各平台预编译的 `.node`（darwin/linux/win32，含 arm64/ia32/musl 变体），
**没有 android**。它在系统里只承担一件事：把 Node 内部模块 id（`internal/modules/esm/loader` 之类）
交给 `require`。cordis 插件加载器与 dsh-app-boot 的 profile 解析都依赖它。

**改法**：`--expose-internals` 启动 Node 后，普通 `require(id)` 就能拿到这些内部模块，
于是把包的入口换成等价 JS（桌面版本身也一直带 `--expose-internals`，语义一致）。

```js
function requireBuiltin(moduleId) { return require(moduleId); }
function isAllowedInternalId(moduleId) {
  try { require.resolve(moduleId); return true; } catch { return false; }
}
function getBindingInfo() {
  return { backend: 'js-expose-internals', platform: process.platform, arch: process.arch };
}
module.exports = { requireBuiltin, isAllowedInternalId, getBindingInfo };
```

**验证**：`dsh web --help` 能打印 web app 自己的帮助（说明 profile 解析走通了）。

## 2. `@deepseek-ai/node-addon-system` 的 flock —— 必须回调

**症状**（最贵的一个：**不报错**）：

用户提问后界面永远停在「深度求索中」，日志没有异常，会话目录只有一个 0 字节的 `session.lock`。

**为什么**：`tryLockExclusive(fd)` 的实现是

```js
const errno = await new Promise((resolve) => { loadBinding().tryLock(fd, resolve); });
```

它在非 linux/darwin 上直接抛 `ERR_FLOCK_UNSUPPORTED_PLATFORM`。把抛错改成「直接 return」后，
`tryLock` 从没调用 `resolve` —— **Promise 永不 settle**，拿锁那一步永久挂起。
这就是「会话永不回复」的真相（不是浏览器、不是流式渲染）。

**改法**：单实例应用没有并发写者，直接回调成功：

```js
return { tryLock(_fd, callback) { queueMicrotask(() => callback(0)); } };
```

**验证**：会话开始落盘，界面正常返回。

## 3. `dsh-session-persistence-jsonl` —— link 换 rename

**症状**：

```
EACCES: permission denied, link
'/data/user/0/<pkg>/files/dshhome/sessions/.../session.v4.jsonl.zstd.<hex>.tmp'
-> '.../session.v4.jsonl.zstd'
```

**为什么**：POSIX 分支用 `link(tmp, final)` 做「不覆盖的原子发布」。Android 的 SELinux 拒绝对
app data 里的文件做 `link(2)`（哪怕 owner 是自己）。

**改法**：捕获 `EACCES/EPERM/EOPNOTSUPP/ENOSYS/EXDEV` 后改用 `rename`。
同盘 `rename` 本身原子，且调用前已检查过目标不存在，语义不变。

## 4. `dsh-ptc-runtime-node` —— 子进程保留 LD_LIBRARY_PATH

**症状**（PTC 模式 `run_code`）：

```
CANNOT LINK EXECUTABLE ".../lib/x86_64/libnode_exec.so": library "libz.so.1" not found
```

**为什么**：PTC kernel 启动子进程时把环境**重建成同名键、值全 undefined**（等于清空）。
桌面/服务器上子进程用系统 node，不需要 loader 路径；Android 上子进程要重新执行 **APK 里那个原生 node**，
没有 `LD_LIBRARY_PATH` 就找不到 libz/libicu。

**改法**：在环境过滤前声明放行集合，**两个 spawn 点都要改**（一次性 kernel 与持久 REPL 各一处）：

```js
const PRESERVED_CHILD_ENV = new Set(["LD_LIBRARY_PATH"]);
const env = Object.fromEntries(Object.keys(process.env).filter(...)
  .map((key) => [key, PRESERVED_CHILD_ENV.has(key.toUpperCase()) ? process.env[key] : void 0]));
```

**验证**：PTC 模式 `run_code` 能返回；标准模式不受影响（继承父进程环境）。

---

## 顺带两个环境参数（不是补丁）

- **`--dns-result-order=ipv4first`**：设备只有 IPv4 路由时，Node 默认 happy-eyeballs 会让
  `fetch` 报 `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` / `fetch failed`。
- **`SSL_CERT_FILE`**：Android 没有 Node 默认可用的系统 CA 路径（Termux 构建按
  `$PREFIX/etc/tls/cert.pem` 编死），需要把 cert bundle 塞进载荷并指过去。
