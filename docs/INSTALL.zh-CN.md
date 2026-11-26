# 刷机与更新

适用：Xiaomi Pad 6 Pro（liuqin，128G），Fedora 45 KDE Plasma Mobile，从 A 槽
启动，没有 Android。分区表保持原厂：`boot_a` 装内核，`userdata` 是唯一的数据
分区（卷标 `LIUQIN_ROOT` 的 ext4，根在 `native-root/` 下），没有 `/boot` 分区。

产物怎么来见 [`BUILD.zh-CN.md`](BUILD.zh-CN.md)。

## 0. 要刷什么

```
boot.img    → boot_a      内核、设备树、initramfs、ABL overlay
rootfs.simg → userdata    整个 Fedora 根文件系统（Android sparse 格式）
```

boot.img 里钉着这次构建的内核版本号，启动时和根里的 `kernel.release` 比对，
不一致就停在 initramfs 的救援 shell。所以两者必须来自同一次构建、一起刷。

## 1. 开始之前

- Bootloader 已解锁，能进 fastboot，电量 30% 以上；
- 分区表是原厂 V14 的那张；
- 刷 `userdata` 会清空数据分区（根和 `/home` 一起），先备份；
- 回滚靠上一套镜像：刷回旧的 `boot.img` + `rootfs.simg`，或者用 V14 线刷包恢复
  原厂系统。

## 2. 第一次安装或重装

artifact 解开后是平铺的一层，没有子目录：

```
boot.img                192 MiB
rootfs.tgz.part-NN      1900 MiB 一片
SHA256SUMS              对 rootfs.tgz 的哈希
fedora-report.txt       这次构建的关键数字
rootfs.manifest.gz      树的清单
native-root.hashes.gz   树的逐文件哈希
kernel-liuqin-*.rpm     内核包（只换内核时用）
```

**Windows（PowerShell）**：

```powershell
# 合并分片。cmd 的通配符按名字排序，片数多了也不用改命令。
cmd /c copy /b rootfs.tgz.part-* rootfs.tgz

# 核对：把下面输出和 SHA256SUMS 里的值比
(Get-FileHash rootfs.tgz -Algorithm SHA256).Hash.ToLower()

# 7-Zip 解两层：rootfs.tgz -> rootfs.tar -> rootfs.simg
7z x rootfs.tgz
7z x rootfs.tar

fastboot flash boot_a   boot.img
fastboot flash userdata rootfs.simg
fastboot reboot
```

**Linux / macOS**：

```sh
cat rootfs.tgz.part-* > rootfs.tgz
sha256sum -c SHA256SUMS
tar -xzf rootfs.tgz

fastboot flash boot_a   boot.img
fastboot flash userdata rootfs.simg
fastboot reboot
```

第一次启动会进 **plasma-setup**（KDE 的首次设置），创建用户、设语言时区。这条线
没有 gnome-initial-setup，也没有预置账户。

进桌面后做两件事：

```sh
# 1. 从 persist 分区取本机的 MAC、蓝牙地址、喇叭校准和传感器数据
sudo sh tools/provision-liuqin-from-persist.sh /
sudo reboot

# 2. 镜像默认约 7 GiB，把它扩到整个 userdata
sudo resize2fs /dev/disk/by-partlabel/userdata
```

原厂 `persist` 分区可能留着没 replay 的 ext4 journal，这时内核对只读挂载会报
`recovery required on readonly filesystem`。脚本先试 `ro`，失败就退到 `ro,noload`，
打一条 warning 后照常取值，全程不写 persist。想彻底修掉，手动 replay 一次：

```sh
sudo umount /dev/disk/by-partlabel/persist 2>/dev/null
sudo mount -o rw /dev/disk/by-partlabel/persist /mnt && sudo umount /mnt
```

## 3. 只更新内核

1. 用新的内核产物重新装配 boot.img（`fedora-rootfs` 工作流的第 5 步，或本地
   `tools/build-liuqin-fedora-boot.sh`）；
2. 平板上下载并安装新的 `kernel-liuqin-*.aarch64.rpm`：

   ```sh
   sudo dnf install ./kernel-liuqin-7.3.0-0.1.g<commit>.aarch64.rpm
   ```

   包是本地打的、没有签名，`dnf` 需要用 `--nogpgcheck`。
3. 关机进 fastboot，`fastboot flash boot_a boot.img`，重启。

这条路不碰 `userdata`，数据保留。

## 4. 更新用户态

树里的任何内容变了（固件、桌面、包）就要重跑 `fedora-rootfs` 工作流，boot.img 和
rootfs 一起换：

1. 备份 `/home`；
2. 跑工作流，下载新的 artifact；
3. 按第 2 节合并、解开、刷 `boot_a` 和 `userdata`；
4. 重启后按第 2 节做一次校准导入，再把 `/home` 放回去。

## 4.5 第一次上机要收集的东西

第一次刷 Fedora 是这条线唯一没验证过的环节。刷之前把上一套 Ubuntu 的
`boot.img` 和 `rootfs.simg` 留在刷机主机上（回滚用）。

刷完按顺序记录：

1. 开机后是进桌面（plasma-setup 的欢迎/建用户界面），还是停在 initramfs 的
   救援 shell；
2. 如果停住：`fastboot` 重新进 bootloader、再 `fastboot boot boot.img` 一次，
   同时接 USB，在刷机主机上 `telnet 192.168.7.2 2323`，把
   `dmesg | tail -50`、`cat /proc/cmdline`、`cat /run/liuqin-firstboot.log` 抓下来；
3. 如果进了桌面：`uname -r`、`getenforce`、`findmnt /`、
   `ls /usr/lib/modules`，以及屏幕有没有花、触控能不能用。

这一轮不追硬件（音频、传感器、指纹都还没移植），只看"能不能到桌面"。

## 5. 启动后检查

冷启动（断电再开，不是重启）逐项看：

| 项 | 怎么看 |
|---|---|
| 内核 | 面板或串口日志到 systemd；`uname -r` 是 `fedora-rootfs` 工作流报的那个版本 |
| 准入 | 没有停在 initramfs 救援 shell |
| 显示/触控 | 桌面出现；`/proc/interrupts` 有 `nt36523`；`/dev/input` 有事件节点 |
| Wi-Fi / 蓝牙 | MAC 和地址来自 persist |
| 音频 | `speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1` 出声 |
| 根分区 | `findmnt /` 是 `LABEL=LIUQIN_ROOT` 的 ext4 |
| 桌面 | Plasma Mobile 能登录、能建用户 |
| SELinux | `getenforce` 是 `Permissive` |

结果写回 [`STATUS.zh-CN.md`](STATUS.zh-CN.md)；没验证过的不要写成可用。

## 6. 回滚

| 情况 | 怎么做 |
|---|---|
| 新内核起不来 | 刷回旧的 boot.img（模块版本要一起回，装旧的 RPM） |
| 新用户态有问题 | 旧的 `boot.img` + `rootfs.simg` 一起刷回 |
| 回 Ubuntu 线 | 刷 `liuqin-install` 线的产物 |
| 回原厂 | V14 线刷包 `flash_all.sh` |

刷机主机上保留上一套 `boot.img` 和 `rootfs.simg`，回滚就靠它们。

## 7. 卡住了看哪里

- 停在 initramfs：USB 网络救援 `telnet 192.168.7.2 2323`，见
  [`RESCUE.zh-CN.md`](RESCUE.zh-CN.md)；
- 空间没长满：`sudo resize2fs /dev/disk/by-partlabel/userdata`；
- 准入被拒：救援 shell 里会有 `persistent root rejected: <原因>` 一行，最常见的
  是 `kernel release mismatch`（boot.img 和 rootfs 不是同一次构建）。
