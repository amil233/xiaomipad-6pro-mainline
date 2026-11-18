# 安装、重装与恢复（128G / A 槽单系统）

适用：Xiaomi Pad 6 Pro（liuqin，**128G**，SM8475），单系统 Ubuntu 26.04，
**无 Android**。不适用于其他容量/改过分区的设备；不要照抄参考项目
（`liuqin-6.17test`，256GB、B 槽、双系统）的安装说明。

> 本机实际经历：用本仓库安装器的 `--layout linux-only` 安装（它写入
> `boot_b` 并 `--set-active=b`），之后手动 `fastboot flash boot_a` +
> `fastboot --set-active=a`，所以现在从 **A 槽**启动。`boot_b` 里留有那次
> 安装写入的 Ubuntu 副本，但**不从 B 启动**。本分支已把安装器的 linux-only
> 目标槽改为 A，新安装不再需要这一步手动修正。

## 1. 前置条件

- Bootloader 已解锁；平板进入 Fastboot；电量 ≥ 30%。
- 原厂 **`V14.0.9.0.TMYCNXM`** 线刷包（唯一支持版本），并知道如何用它恢复原厂。
- 个人文件已备份到平板以外；安装会清空/缩小 `userdata`。
- 主机：Linux、Python 3.11+、Android platform-tools、正常 USB 网络。
- 安装包：`boot.img`、`installer.img`、`rootfs.tar.gz`、`bundle.json`、
  `install.py`、`liuqin_layout.py` 必须同版本；未验收包需 `--allow-unverified`。

安装器在设备侧核对（容量单位为 **512 字节扇区**）：

| 项目 | 允许值 |
|---|---|
| userdata 分区名 | `userdata`，唯一，位于第一颗 UFS（sda） |
| sda 逻辑块大小 | 4096 |
| userdata 扇区数 | ≥ 33554432（16 GiB） |
| Fastboot 身份 | `product: liuqin`、`unlocked: yes` |

安装器不会修改 `persist`，不会重新锁定 Bootloader。型号/身份不符时必须停止，
不要绕过检查。

## 2. 备份

`--backup DIR` 会在改分区表前保存并校验 `boot_a`、`boot_b`、`persist`
与 GPT 主备两份。备份目录必须是新目录、放在安装包目录之外，并保持私密。
已经装好、只重装系统时可用 `--keep-home`；`--no-backup` 只允许已有受支持
布局的重装，不允许首次安装或恢复分区表。

## 3. 安装（单系统）

```sh
python3 install.py --bundle . --serial DEVICE_SERIAL \
  --backup /path/to/new-private-backup --erase-userdata --layout linux-only
```

- `--layout linux-only`：删除 `userdata`，在磁盘尾部建 `linux_root`（默认 32G）
  与 `linux_home`（剩余全部）；不再保留 Android。
- 交互确认需输入 `YES`；脚本环境显式加 `--yes`。
- 安装器会临时启动 `installer.img`，等 USB 网络，备份、改表、格式化、
  安装 rootfs、写入本机校准与地址，最后写 boot 并重启。
- **不要**使用 `--layout dual`、`--rom-dir`、`--android-size`、`--android-boot`：
  本分支已禁用 Android/双系统路径，传入会直接报错。

### 3.1 旧安装器的 A 槽修正（本机做过一次）

旧版 `linux-only` 把 boot 写到 `boot_b` 并 `--set-active=b`。要在 A 槽启动，
在 Fastboot 下执行（镜像必须零填充到 192 MiB 分区大小，即 201326592 B）：

```sh
cp /path/to/boot.img boot-padded.img
truncate -s 201326592 boot-padded.img
fastboot -s DEVICE_SERIAL flash boot_a boot-padded.img
fastboot -s DEVICE_SERIAL --set-active=a
```

回读核对后再重启。`boot_b` 可以保留原副本，但不要依赖它启动。
本分支的安装器已改为直接写 `boot_a`/`--set-active=a`，新装不需要这步。

## 4. 重装与调整分区

- 保留 `/home` 重装：`--keep-home`（不可与 `--android-size`/`--root-size` 同用）。
  会先核对 `liuqin_home` 的 `LIUQIN_HOME` 卷标并 `e2fsck -p`，不符即停止。
- 调整切分比例：先恢复出厂分区表，再完整重装：

```sh
python3 install.py --bundle . --serial DEVICE_SERIAL \
  --restore-partition-table /path/to/private-backup
```

恢复出厂表后设备上没有可用系统，需继续完整安装或用 V14 原厂包清刷。

## 5. 救援与已知问题

- 安装时加 `--enable-rescue` 可从首启开放救援通道；默认关闭。
  平板上可 `sudo liuqin-rescue on/off/status`，开启后 `192.168.7.2:2323`
  提供免认证 root，只能用于可信直连 USB，不要转发到网络。
- 部分机器启动 SLPI 会复位：`sudo touch /etc/liuqin-slpi-disabled` 后重启，
  期间自动旋转不可用；删除标记并重启恢复。不要改
  `/etc/systemd/system/liuqin-slpi.service`（boot 会校验）。
- 亮度和关机充电的已知问题见 `STATUS.zh-CN.md` §6。

## 6. 恢复原厂 / 回到 Android

本机没有 Android，也不提供"重启到 Android"。要回原厂，只能用
**V14.0.9.0.TMYCNXM** 的完整 Fastboot 清刷流程（会清除 Ubuntu 与
`linux_root`/`linux_home`）：

```sh
# 在解包后的 V14 原厂包目录
sh flash_all.sh
```

- 不要用 `OS2.0.6.0` 或其他 ROM 的包；那是参考项目的 ROM。
- 不要用 `flash_all_lock.sh` 或保留数据的变体，除非你明确要重新上锁/保留数据。
- 不要恢复其他平板的 `persist`；校准与设备地址必须来自本机。
- 清刷后 Bootloader 状态、分区表都回到原厂；重新安装 Ubuntu 走 §3。
