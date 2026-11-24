# 刷机与更新

适用：Xiaomi Pad 6 Pro（liuqin，128G），Ubuntu 26.04.1 arm64（新镜像基线），从 A 槽启动，
没有 Android。分区表保持原厂：`boot_a` 装内核，`userdata` 是唯一的数据分区
（根和 `/home` 都在里面），没有 `/boot` 分区。

产物怎么来见 [`BUILD.zh-CN.md`](BUILD.zh-CN.md)。

## 0. 要刷什么

```
boot.img    → boot_a      内核、设备树、initramfs、ABL overlay
rootfs.img  → userdata    整个 Ubuntu 根文件系统
```

boot.img 里有这份 rootfs 的文件哈希清单，启动时会核对。**只换内核**时清单
不变，刷 boot.img 就行；**动了用户态**时清单会变，boot.img 和 rootfs 必须
一起换。

## 1. 开始之前

- Bootloader 已解锁，能进 fastboot，电量 30% 以上。
- 分区表是原厂 V14 的那张：`boot_a`、`userdata` 都在。现在这台平板还是旧布局
  （`linux_root` + `linux_home`，`userdata` 被旧安装器删掉了），换成单数据分区
  要先刷 V14 整包 `flash_all.sh`，会清空整机；之后不再需要动分区表。
- 刷 `userdata` 会清空数据分区（根和 `/home` 一起），先备份。
- `boot_b` 不参与启动，也不是回滚方式；回滚用 `repack/` 或旧 bundle 里的
  boot.img。

## 2. 第一次安装或重装

在刷机主机上执行，boot.img 和 rootfs.tar.gz 来自同一个 bundle：

```sh
fastboot flash boot_a   bundle/boot.img
fastboot flash userdata out/dist/rootfs.img
fastboot reboot
```

刷完把 bundle 里的两个文件拷到开发机，覆盖同名文件：

```sh
cp bundle/native-root.hashes      <repo>/out/native-root/native-root.hashes
cp bundle/liuqin-firstboot.cpio.gz <repo>/out/initramfs-liuqin/liuqin-firstboot.cpio.gz
```

这两个文件是 boot.img 里那份清单的来源。下次只换内核时，脚本会用它们核对
新内核和实际 rootfs 是否匹配。

第一次启动会直接进 `gnome-initial-setup`，创建用户。进桌面后做两件事：

```sh
# 1. 从 persist 分区取本机的 MAC、蓝牙地址、喇叭校准和传感器数据
sudo sh tools/provision-liuqin-from-persist.sh /
sudo reboot

# 2. 镜像默认只占 6–8 GB，把它扩到整个 userdata
sudo resize2fs /dev/disk/by-partlabel/userdata
```

不做第 1 步也能开机，但 Wi-Fi/蓝牙地址、喇叭校准和传感器会缺或使用默认值。
第 1 步只在重装 rootfs 后需要，因为那些数据在根分区里，会被刷掉。

## 3. 只更新内核

先在平板上装新的内核 deb，再进 fastboot 刷 boot.img：

```sh
# 1. 平板上的 Ubuntu 里（只改磁盘上的文件，正在运行的内核不受影响）
sudo dpkg -i liuqin-kernel_0.1_arm64.deb

# 2. 关机，音量键进 fastboot

# 3. 刷机主机
fastboot boot repack/<commit>-boot/boot-liuqin-firstboot.img   # 可以先试
fastboot flash boot_a repack/<commit>-boot/boot-liuqin-firstboot.img
fastboot reboot
```

- 装完 deb 后旧 boot.img 已经找不到对应的内核模块，不要再用它启动；直接进
  fastboot 刷新的。
- 内核模块和版本号由 deb 更新，boot.img 只换 Image、设备树和 initramfs。
- 这条路不碰 `userdata`，数据保留。

## 4. 更新用户态

用户态一变，boot.img 里的文件清单就过期，两样要一起换：

1. 先备份 `/home`（`userdata` 会被整块重写）；
2. 构建机（或集成仓的 image workflow）出新 bundle；刷机主机生成 `rootfs.img`
   （BUILD 第 5 节）；
3. `fastboot flash boot_a bundle/boot.img`，
   `fastboot flash userdata out/dist/rootfs.img`；
4. 重启，按第 2 节做一次校准导入，再把 `/home` 放回去。

不能只装新的 device-support 而不换 boot.img：下次启动时文件清单对不上，
initramfs 会拒绝挂载根文件系统。

## 5. 启动后检查

冷启动（断电再开，不是重启）逐项看：

| 项 | 怎么看 |
|---|---|
| 内核 | 面板或串口日志到 systemd，没有 oops；`uname -r` 是预期的版本 |
| 显示/触控 | 120 Hz；`/proc/interrupts` 有 nt36523，`/dev/input` 有事件节点 |
| Wi-Fi / 蓝牙 | MAC 和地址来自 persist |
| 音频 | `speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1` 出声 |
| 根分区 | `findmnt /` 是 `LABEL=LIUQIN_ROOT` 的 ext4，`/home` 在同一个文件系统上 |
| 桌面 | 能登录、能建用户 |

结果写回 [`STATUS.zh-CN.md`](STATUS.zh-CN.md)；没验证过的不要写成可用。

## 6. 回滚与恢复

| 情况 | 怎么做 |
|---|---|
| 新内核能启动但有问题 | 在系统里装回旧的内核 deb，再刷回旧 boot.img |
| 新内核完全起不来 | 旧 boot.img 和旧 rootfs.img 一起刷回（新 deb 已经换掉了模块，单刷 boot.img 对不上） |
| 新用户态有问题 | 旧 bundle 的 boot.img 和 rootfs.img 一起刷回 |
| 回原厂 | V14 线刷包 `flash_all.sh`；`out/boot_a.img` 留档 |

刷机主机上保留上一套 bundle 和 `out/dist/`，回滚就靠它们。

## 7. 卡住了看哪里

- 停在 initramfs：USB 网络救援 `telnet 192.168.7.2 2323`。
- 空间没长满：`resize2fs /dev/disk/by-partlabel/userdata`。
- 刷之前先看 `boot-liuqin-firstboot.info`：命令行、ramdisk、ABL 信息都在里面。
- 其它问题：STATUS 的“已知问题”。
