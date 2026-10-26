# 三、把 shell 用户态一起塞进 APK（可选）

目标：不装 Termux 也能给 agent 一个真 shell（`bash -c` 有 `ls/grep/sed/awk/find/tar/xargs`）。

## 组成

| 打进 jniLibs | 说明 |
|---|---|
| `libbash_exec.so` | Termux `bash`（5.3.20） |
| `libbusybox_exec.so` + `libbusybox.so.1.38.0` | Termux `busybox` 包是「瘦 stub + 共享库」 |
| `libreadline.so.8 / libncursesw.so.6 / libiconv.so / libpcre2-8.so / libandroid-support.so` | 上述二进制的依赖（带版本号的同样需要注入，见文档二） |

Termux 包列表：`bash busybox libandroid-support libandroid-selinux pcre2 libiconv readline ncurses`。

## 两个坑

### 1) 符号链接必须放在可写目录

可执行文件在 nativeLibraryDir（只读），但 applet 需要一堆名字。做法：在
`files/home/bin/` 里建符号链接指向 nativeLibraryDir 里的二进制。**链接本身在 app data 里没关系**，
内核只对**解析后的目标**做执行权限检查（目标是 `apk_data_file`）。

### 2) busybox 按 argv[0] 派发

直接执行 `libbusybox_exec.so` → `applet not found`。必须建一个名字就叫 `busybox` 的链接再调用它，
`busybox --list` 才能拿到 applet 列表（实测 276 个）。

### 3) 重装应用后链接会失效

`nativeLibraryDir` 每次安装都会换路径，旧的符号链接变成悬空路径，`spawn bash` 报
`EACCES/ENOENT`。启动时要**比对链接目标并重建**（别用 `exists()` 判断——悬空链接返回 false，
而 `createSymbolicLink` 又会抛 `FileAlreadyExistsException`）。

## 环境注入

```
PATH=<files>/home/bin:<nativeLibraryDir>:/system/bin:/system/xbin
HOME=<files>/home
PREFIX=<files>/home
LD_LIBRARY_PATH=<nativeLibraryDir>
```

于是运行时里 `bash -c` 命中的就是这套用户态。实测 agent 的 bash 工具输出：

```
GNU bash, version 5.3.20(1)-release (x86_64-pc-linux-android)
HOME=/data/user/0/<pkg>/files/home
```

## 许可提醒

bash 是 GPLv3、busybox 是 GPLv2、readline 是 GPLv3。**随 APK 分发**就要履行 GPL（附源码或书面要约）；
自己用不分发则不受限。
