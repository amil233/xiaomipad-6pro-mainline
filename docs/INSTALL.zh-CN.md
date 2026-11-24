# 刷机与更新（128G，A 槽单系统，单数据分区）

适用：Xiaomi Pad 6 Pro（liuqin，SM8475，**128G**，天马 `m81_36_02_0a`），
Ubuntu 26.04 arm64 桌面，**从 A 槽直接启动**，**没有 Android**。

分区表保持**原厂**：`boot_a` 换成我们的 boot.img，`userdata` 是唯一的数据
分区（`LABEL=LIUQIN_ROOT`，根和 `/home` 都在这一块 ext4 上）。**不建**
`linux_root`/`linux_home`，也**没有** `/boot` 分区。

产物从哪来、怎么装配，见 [`BUILD.zh-CN.md`](BUILD.zh-CN.md)。本文只讲上机。

## 0. 流程总览

```
boot.img    ──fastboot flash──▶ boot_a     内核 + DTB + initramfs + ABL overlay
rootfs.img  ──fastboot flash──▶ userdata   唯一数据分区（ext4，根 + /home）
                                    │
                                  重启
                                    ▼
                 首启 provision ──▶ resize2fs ──▶ 冷启动验收
```

- **只更新内核**：换 `boot.img` + 在系统里装新内核 deb（§3）。
- **更新用户态**：`boot.img` 与 `rootfs.img` 成对换（§4）；整块 `userdata`
  重写，`/home` 一起清空，先备份。
- **重启前两半都要到位**：Image 与模块/`kernel.release` 必须同一 release。

## 1. 一次性前提

- Bootloader 已解锁，平板能进 fastboot，电量 ≥30%。
- 分区表是**原厂 V14.0.9.0.TMYCNXM** 的那张：`boot_a`、`userdata` 都在。
  能进系统时用 `lsblk -o NAME,PARTLABEL,LABEL` 确认 `userdata` 存在；
  **本流程不创建、不修改任何分区**。
- **当前设备是旧布局**：2026 年用参考项目的安装器装过，分区表被改成了
  `linux_root`(#36) + `linux_home`(#37)，`userdata` 已被删除。迁到单数据分区
  布局只能恢复原厂分区表（V14 线刷包的 `flash_all.sh`），这会清空整机；
  先备份个人文件，再按 §2 装一遍。这是最后一次分区表操作。
- 刷 `userdata` 会清空整块数据分区（根 + `/home`）；刷 `boot_a` 不清数据。
- `boot_b` 不参与启动，也不是回滚槽。**迁移后 `repack/` 里的旧镜像不能启动新根**
  （契约是按旧 rootfs 打的）；第一次用新 bundle 装出来的就是新基线，之后回滚用
  保留的 bundle。

## 2. 首次安装 / 重装 rootfs

刷机主机上（产物来自同一个 CI bundle）：

```sh
fastboot flash boot_a   bundle/boot.img
fastboot flash userdata out/dist/rootfs.img
fastboot reboot
```

刷完把这套 bundle 的两个文件拷到开发机，覆盖同名文件：

```sh
cp bundle/native-root.hashes    xiaomipad-6pro-mainline/out/native-root/native-root.hashes
cp bundle/liuqin-firstboot.cpio.gz \\
   xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz
```

它们是 boot.img 里那份 root 契约的来源（清单 + 携带契约的 initramfs）。下一轮
“只换内核”的装配会用它们核对新 Image 与实机 root 仍然配套（BUILD §3）。

首启应直接进 `gnome-initial-setup`，创建用户（镜像里没有预置账户，也没有
自动登录）；这条流程第一次走时记下实际现象，回写 STATUS。

进桌面后做两件一次性的事：

```sh
# 1. 把本机校准从 persist 取回来（只读挂载 persist，不写它）
sudo sh tools/provision-liuqin-from-persist.sh /      # 脚本在仓库里，拷到平板执行
sudo reboot

# 2. 首次启动后把文件系统长到整个 userdata（镜像默认只占 6–8G）
sudo resize2fs /dev/disk/by-partlabel/userdata
```

provision 写入 WLAN MAC、蓝牙地址、四声道 CS35L41 校准和传感器 registry；
**只在 rootfs 被重装后需要**（这些数据在根分区里，会被刷掉）。跳过也能开机，
但 Wi-Fi/蓝牙地址、外放校准、传感器会缺失或退回默认值。

首启后按 §5 验收。

## 3. 只更新内核（日常）

内核更新是**模块 + Image 两半**：deb 换
`/usr/lib/modules/<release>` 和 `/usr/share/liuqin/kernel.release`，
boot.img 换 Image/DTB/initramfs。顺序不能反：

```sh
# 1. 平板当前系统里（只换盘上文件；运行中的旧内核不受影响，模块已在内存里）
sudo dpkg -i liuqin-kernel_0.1_arm64.deb

# 2. 立刻进 fastboot，不要正常重启回系统（旧 boot.img 已经找不到旧模块了）
#    关机 → 音量键进 fastboot；或从刷机主机 adb reboot bootloader

# 3. 刷机主机
fastboot boot repack/<sha6>-boot/boot-liuqin-firstboot.img   # 可选试跑，不写分区
fastboot flash boot_a repack/<sha6>-boot/boot-liuqin-firstboot.img
fastboot reboot
```

- 试跑此时才有意义：第 1 步之后盘上的模块已经是新 release，新 Image 与它们匹配。
- 契约不用重建：它只锁用户态设备文件，内核文件故意不在里面（见 BUILD §3）。
- 装完 deb 后旧 boot.img 已经和盘上的模块对不上，不要再拿它启动；回滚按 §6
  成对处理。
- 这条路径**不碰 `userdata`**，`/home` 和数据都保留。

## 4. 更新用户态（device-support、sensors、firmware 等）

用户态一改，boot.img 里的契约就过期，必须**成对**换：

1. **先备份 `/home`**（单数据分区的代价）：整块 `userdata` 会被重写；
2. CI 出新的整机 bundle：`boot.img` + `rootfs.tar.gz`；
3. 刷机主机生成 `rootfs.img`（BUILD §5）；
4. `fastboot flash boot_a bundle/boot.img`，再
   `fastboot flash userdata out/dist/rootfs.img`；
5. 重启 → 首启 → provision（§2）→ 把 `/home` 放回 → 按 §5 验收。

不能只 `dpkg -i` 新 device-support 而不换 boot.img：下次冷启动 initramfs 会发现
契约不符并拒绝挂载根文件系统。`repack/9a81b1a-contract-boot/` 就是 2026-11-18
为这种“用户态先动、boot 后补”的情况补的一张镜像。

为什么不再拆 `/home`：少一个分区、少一条挂载依赖，layout 就是原厂那张表；
代价是用户态更新会连 `/home` 一起重写，必须自己先备份。

## 5. 冷启动验收

每次换内核或换用户态后，冷启动（不是热重启）逐项确认：

| 项 | 怎么看 |
|---|---|
| 内核 | 面板/串口日志到 systemd，无 oops/panic；`uname -r` 是预期 release |
| 显示/触控 | 120 Hz 桌面；`/proc/interrupts` 有 nt36523，`/dev/input` 有事件节点 |
| Wi-Fi / 蓝牙 | MAC 与地址来自 persist（`liuqin-wlan-mac`、`liuqin-bt-public-addr`） |
| 音频 | `speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1` 与桌面播放均出声（见 `AUDIO.zh-CN.md`） |
| 根分区 | `findmnt /` 是 `LABEL=LIUQIN_ROOT` 的 ext4；`/home` 在同一个文件系统上 |
| GNOME | 能登录、能建用户、USB 救援单元在 |

结论写回 [`STATUS.zh-CN.md`](STATUS.zh-CN.md)；没验过的项不要写成可用。

## 6. 回滚与恢复

| 情形 | 处置 |
|---|---|
| 新内核能启动但有问题 | 系统里 `dpkg -i` 旧内核 deb，再 flash 回旧 boot.img（两者成对） |
| 新内核完全起不来 | 旧 boot.img + 旧 rootfs.img 成对刷回：新 deb 已经把 root 里的模块/release 换掉，单刷 boot.img 对不上（没有旧 `rootfs.img` 就用旧 bundle 的 `rootfs.tar.gz` 现场生成） |
| 新用户态异常 | 旧 bundle 的 boot.img + rootfs.img 成对刷回（`/home` 同样先备份） |
| 完全回原厂 | V14.0.9.0.TMYCNXM 线刷包 `flash_all.sh`（见 STATUS §7）；`out/boot_a.img` 留档 |

所以刷机主机上**保留上一套 bundle 与 `out/dist/`**（至少 `boot.img`、
`rootfs.tar.gz`/`rootfs.img`），这是内核回滚和用户态回滚的唯一来源。

## 7. 故障排查

- 卡在 initramfs：USB 网络救援 `telnet 192.168.7.2 2323`（见 STATUS §2）。
- 空间没长满：`resize2fs /dev/disk/by-partlabel/userdata`（§2 第 2 步）。
- 刷前先看 `repack/<sha6>-boot/boot-liuqin-firstboot.info`：cmdline、ramdisk、
  ABL 元数据都在里面；换内核时若 cmdline 和 ramdisk 没变，差异只在 Image/DTB。
- 已知问题与待办：STATUS §6。
