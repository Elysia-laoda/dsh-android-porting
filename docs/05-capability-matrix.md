# 五、权限能力矩阵（Android 17 实测）

同一组命令，三种上下文。`shell` 这一列就是 **Shizuku 能给到的面**（Shizuku 以 uid 2000 转发命令）。

| 命令 | root | shell（Shizuku） | app（普通运行时） |
|---|---|---|---|
| `id` | `uid=0` | `uid=2000(shell)` | `u0_aXXX` |
| `ls /data/data` | ✅ | ❌ Permission denied | ❌ |
| `pm list packages` | ✅ | ✅ | ❌ |
| `ls /sdcard` | ✅ | ✅ | ❌（未申请存储权限时） |
| `settings get secure android_id` | ✅ | ✅ | ❌ |
| `cat /proc/version` | ✅ | ✅ | ✅ |
| `wm size` | ✅ | ✅ | ❌ |

结论：

- **Shizuku 给的是「设备管理面」**：pm / settings / sdcard / wm / am 都能用，足以做自动化；
  但 `/data/data` 仍然进不去 —— 它不是 root。
- **应用自身拿不到 root**：AOSP userdebug 的 `/system/xbin/su` 是 `-rwsr-x--- root shell`（4750），
  只有 shell 组能执行。真机上要给 agent root，只能走 Magisk 的 su（会弹授权）。

## 附带的两个实现事实

- **Shizuku 客户端（13.1.5）里 `Shizuku.newProcess` 是 private**（`javap -p` 可验），
  要执行命令必须 `bindUserService` + 自己写 AIDL 服务端（`destroy()` 的方法 id 用 `16777114`，Shizuku 服务端保留）。
- 授权只用 `Shizuku.checkSelfPermission() / requestPermission()`；判定「服务是否在跑」用 `pingBinder()`，
  不要只看包名是否安装（Android 11+ 包可见性会误判，Sui 更是没有这个包）。
