# Upstream note: four patches an Android port needed

Context: we run the DSH runtime inside an Android APK (Node 26.12.1 from Termux, Android 17 / API 37).
This repo is not another Android app — it is the patch set and the measurements, published because every
Android port hits the same walls:

<https://github.com/Elysia-laoda/dsh-android-porting>

## Two patches that look platform-generic

**1. `@deepseek-ai/node-addon-system` — `flock` on an unsupported platform never settles**

`tryLockExclusive(fd)` builds `new Promise((resolve) => { loadBinding().tryLock(fd, resolve); })`.
On a platform without a binding, `loadBinding()` throws `ERR_FLOCK_UNSUPPORTED_PLATFORM` — that part is fine,
but if anything turns it into "return early" the callback never fires and the await hangs forever.
On Android this showed up as *every turn silently stuck in "thinking"*, with a 0-byte `session.lock` on disk
and no error anywhere. A callback-based contract that can be violated without a signal is easy to trip over;
calling back with an explicit error (or a documented no-op success for single-instance hosts) would make the
failure mode loud.

**2. `@deepseek-ai/dsh-session-persistence-jsonl` — `link(2)` is denied inside app data**

The POSIX publish path uses `link(tmp, final)` for a no-clobber atomic publish. Android's SELinux denies
`link(2)` on files under the app data directory (EACCES), so materializing a session fails on the first turn.
A `rename` fallback for `EACCES/EPERM/EOPNOTSUPP/ENOSYS/EXDEV` keeps the semantics (same filesystem, atomic,
and the existing existence check already ran).

## Two that are Android-specific (probably not upstream material)

- `node-addon-require-builtin` has no android prebuild; since the only capability used is
  `require("internal/...")`, running Node with `--expose-internals` and a JS shim is enough.
- `dsh-ptc-runtime-node` rebuilds the child environment with every value cleared; on Android the child
  re-executes the *same* native binary, so `LD_LIBRARY_PATH` has to survive (otherwise `CANNOT LINK ... libz.so.1`).

## Verified / not verified

Verified on Cuttlefish / Android 17 (x86_64): the four patches, native payload loading, 276 busybox applets,
in-app login popup, mobile settings layout and a real agent turn against the live API.
Not verified: arm64 hardware, and Shizuku shell execution (the Shizuku server would not start on the emulator).

Not asking for a merge — CONTRIBUTING is explicit that community packages are a first-class outcome. Posting
in case the first two are interesting on the platform-portability axis, and in case the notes save someone
else a week.

---

补充（中文一句话）：Android 移植时踩到的四个坑（flock 回调、link→rename、require-builtin、PTC 子进程环境），
已整理成可 `git apply` 的补丁与实测记录；前两个看起来是平台无关的健壮性问题。
