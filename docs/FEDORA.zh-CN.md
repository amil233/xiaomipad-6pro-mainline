# 把平板换成 Fedora KDE Plasma Mobile（进行中）

一句话：平板上的系统从 Ubuntu 26.04.1 + GNOME 换成 Fedora 45 的 KDE Plasma
Mobile，根文件系统仍然放在 `userdata` 的 ext4 上，启动方式不变。

这份文档写在这个分支（`liuqin-installer-fedora`）上。Ubuntu 那条线的东西
（`INSTALL.zh-CN.md`、`BUILD.zh-CN.md`、`STATUS.zh-CN.md` 以及原来的 workflow）
保持原样，不在这里改。

## 为什么要单独开两条分支

换发行版要动的东西不少：取根的方式、打包格式、桌面定制、安全模块。混在
Ubuntu 那条线上会把已经能用的文档和流程搅乱，也没法对比。所以：

| 仓库 | 分支 | 干什么 |
|---|---|---|
| 内核仓 `linux-sm8450-liuqin` | `liuqin-7.3-fedora` | 内核代码和驱动与 `liuqin-7.3` 完全一样；这个分支只是让 CI 也在这里构建，将来内核侧的 Fedora 改动也只落在这里 |
| 集成仓 `xiaomipad-6pro-mainline` | `liuqin-installer-fedora` | 取 Fedora 的根、把内核和设备文件打成 RPM、装配镜像、新的 workflow |

## 哪些东西不变

`boot.img` 的组成、initramfs（`initramfs/init`）、根文件的哈希清单、
分区表（`boot_a` + `userdata`）、`provision-liuqin-from-persist.sh`、
`resize2fs`、以及把镜像打成 tgz 分片再上传的方式。

## 换成什么

| 现在（Ubuntu 线） | Fedora 线 |
|---|---|
| 根来自 Ubuntu ISO 里的 casper | 根来自 Fedora Live ISO 里 ext4 的 `rootfs.img` |
| `dpkg-deb` 打 5 个 deb，chroot 里 `apt-get` + `dpkg -i` | `rpmbuild` 打 RPM，chroot 里 `dnf install` |
| 内核包是 `.deb` | 内核先打成**一个** RPM |
| 桌面是 GNOME，定制在 `device/gnome-overlay` | 桌面是 Plasma Mobile，定制要重写 |
| 内核里只有 AppArmor，SELinux 没编进去 | 内核编上 SELinux，先用 permissive |
| 根是 ext4 | 还是 ext4（不用 btrfs） |

## 后续行动（2026-11-27 排定）

**A. 等这次 CI（`0a0e7c9`）**：确认建号、`liuqin-device` 安装、`assemble`、
`boot.img`、ext4、打包全过。不过就修，不再往下叠。

**B. 传感器栈，分三小步，每步都要 CI 绿：**

1. `hexagonrpcd`：按 `device/sensors/sources.manifest` 取源码，打
   `device/sensors/patches/0001`、`0002`，在 `fedora:45` 容器里 meson/ninja 编，
   产物先进 `liuqin-sensors` RPM（只装二进制 + 依赖，不带单元）。
2. `iio-sensor-proxy`：先比对 3.9 的上游是否已含六份补丁里的某几份，只保留仍然
   需要的，逐份在新上下文里重打；编过之后放到 `/usr/local/libexec/liuqin-iio-sensor-proxy`，用 drop-in 改
   `ExecStart` 指过去；Fedora 包的单元、udev 规则和 bus/polkit 策略保持不动。
3. 单元与数据：`liuqin-slpi.service`、registry 目录、`fastrpc` 权限（已就位），
   并让 provision 导入的 registry 被真正读到。

**C. 一次性刷机**：A + B 全绿之后出镜像，一次刷完，验证清单：

- `getent passwd fastrpc` 有输出；`ls -l /dev/fastrpc-adsp` 是 `fastrpc:fastrpc 660`；
- `sudo liuqin-rescue on` 能起监听，Windows 上 `telnet 192.168.7.2 2323` 进得去；
- provision 跑完 `registry=<数字>`，重启后音频出声
  （`speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1`）；
- 传感器：`iio-sensor-proxy` 能看到加速度计（`monitor-sensor` 或 KDE 的传感器页）。

**D. 之后（按价值排）**：电源键策略、指纹、相机；SELinux 从 permissive 收紧；
`device/gnome-overlay` 只保留 UCM2，其余目录删掉，减少误读。

**E. 长期**：跟 Fedora 45 的更新（`dnf upgrade` 已在设备上验证可用），内核换代
时重新出 boot.img。

## 刷机的节奏：攒成一批再刷

刷整镜像要十几分钟，另外还要重装校准、重建用户，所以不按提交刷。规则是：

- CI 上能验证的（取根、打包、装 RPM、装配、镜像检查）随时跑，一个提交也可以；
- **上机只在这个批次的内容都进了 CI 产物之后做一次**。

下一批准备一起刷的内容：

1. 传感器栈（`hexagonrpcd` + 打过补丁的 `iio-sensor-proxy`，见下一节）；
2. `fastrpc` 账户和 `/dev/fastrpc-*` 的权限规则（已在代码里，等这次 CI 确认）；
3. USB telnet 救援通道（已在代码里，`liuqin-rescue on`）；
4. 音频出声的确认（不需要改代码，刷完跑 provision + 重启即可验）。

所以现在这版镜像可以先不刷——等传感器栈进了产物，一次刷到位。

## 传感器栈怎么移植（2026-11-27 定下的路线）

平板上查过：Fedora 仓库里**没有** `hexagonrpc` 包；`iio-sensor-proxy` 是 3.9。
所以没有"直接用发行版的包"这条捷径，按移植走。

要搬的东西在 Ubuntu 线里已经齐了：

- 源码：`device/sensors/sources.manifest`（三个仓库，按 commit 固定）；
- 补丁：`device/sensors/patches/` 里两份 `hexagonrpcd` 补丁（SSC registry 版本
  兄弟文件、`sns_registry` 属性 shim）+ 六份 `iio-sensor-proxy` 补丁（预占位冷插、
  轮询串行化、释放取消、可用性广播、冷插门）；
- ROM 侧配置：`device/sensors/rom`（已跟踪）。

现在的 `tools/build-liuqin-sensors-stack.sh` 是**在 Ubuntu 根文件系统上**用
apt + overlay 编的，Fedora 上跑不了。做法是加一个 Fedora 版：
`tools/build-liuqin-fedora-sensors.sh`，在 `fedora:45` 容器里取源码、打同样的补丁、
meson/ninja 编，产物打成 `liuqin-sensors` RPM，内容包括：

- `/usr/bin/hexagonrpcd`、它的 systemd 单元；
- `/var/lib/liuqin-sensors/sensors/registry`（由 provision 从 persist 导入；
  `-R` 前缀之下的布局见本文件后面的映射表）以及同级的 `sns_reg.conf`、`config/`；
- 打过补丁的 `iio-sensor-proxy` 二进制（装在 `/usr/local/libexec/`，由 drop-in
  改 `ExecStart`；单元、udev 规则、bus/polkit 策略仍由 Fedora 的包提供）。

两个待定的点：

1. `iio-sensor-proxy` 3.9 是否已经包含我们那六个补丁里的某些（上游可能在 3.8/3.9
   合了），要先看 changelog，能省的补丁就别搬；
2. 六份补丁是针对 3.x 具体版本的上下文，3.9 上可能不干净地应用，需要重新对齐。

## 还没做、但上机前必须做的一件事

initramfs 的准入检查（`initramfs/init`）是按 Ubuntu + GNOME 写的：它要求
`/usr/sbin/gdm3`、`/usr/bin/gnome-shell`、电源键、传感器、Wacom 锁等大约 40 个
文件和一大堆启用关系，缺一个就拒绝挂载这个根。Fedora 树上没有这些，所以
Fedora 线要加自己的准入分支（判据只留：根标记、systemd、内核模块与
`kernel.release` 一致、`ID=fedora`）。这是第 3 步剩下的关键一块，做完才能出
boot.img。

## 分五步，每步的"算过"标准

1. **取出 Fedora 的根。** 下载 Live ISO、核对哈希、解开，得到一棵能 `chroot`
   进去的目录树，并记录清单。
   算过：`chroot` 里能执行 `rpm -qa`，`systemd` 在，树的大小能放进 8 GiB 镜像。
2. **内核配好并打成一个 RPM。** 内核里加 SELinux，把 Image 和模块打成一个
   RPM，装进第 1 步的树里。
   算过：装完后 `/usr/lib/modules/<版本>/modules.dep` 存在，现有的根目录检查
   （`systemd` 在、标记文件在、`kernel.release` 在）能通过。
3. **装配成镜像。** 生成 ext4 的 `rootfs.img`、配套 `boot.img`、哈希清单，
   打成 tgz 分片。
   算过：`e2fsck` 通过、卷标是 `LIUQIN_ROOT`、`rootfs.img` 里有 `native-root/`
   和内核模块。
4. **第一次上机。** 刷 `boot_a` 和 `userdata`，进 Plasma Mobile，能建用户。
   算过：冷启动三次都进桌面；`provision-liuqin-from-persist.sh` 和
   `resize2fs` 按 `INSTALL.zh-CN.md` 第 2 节走通。
5. **收尾。** 把 GNOME 那套定制换成 KDE 的等价物，SELinux 从 permissive 收紧，
   硬件逐项检查。
   算过：每项硬件有明确结论，能回滚到 Ubuntu 线。

前四步里前三步都在 CI 上做，不碰平板；第 4 步才需要平板。

## 现在做到哪里

- 分支已建好。内核分支多了一条 CI 触发规则（`liuqin-7.3-fedora` 也会构建），
  并且构建时会去取集成仓的 `liuqin-installer-fedora` 分支，这样用到的是这份
  配置（带 SELinux），不会取到 Ubuntu 线那份。
- 内核的 SELinux 开关写进了 `device/configs/liuqin-fedora.config`，并且加进了
  `kernel/source.json` 的配置列表，所以这个分支构建出来的内核带 SELinux。
- **第 1 步已跑通**（workflow 15 分钟）：Fedora 45 KDE Mobile 的根 6107 MiB、
  139,950 个文件、1719 个包；`plasma-mobile 6.8.1`、`plasma-workspace 6.8.1`、
  `plasma-setup 6.8.1`、`selinux-policy-targeted 45.23`、`systemd 262` 都在；
  SELinux 配置是 `enforcing`，策略已装好。自带内核是 7.2.11，`/boot` 占 515 MiB。
  这个根能直接放进 8 GiB 的 ext4 镜像。
- **第 2 步已跑通**：`kernel-liuqin` 包装进树里，756 个模块，树从 6107 MiB 降到
  5377 MiB（Fedora 自带的内核包和 515 MiB 的 `/boot` 都清掉了）。
- 第 3 步开始：`tools/build-liuqin-fedora-rootfs.sh` 负责把树整理成能启动的根，
  现在做三件事——写 `/etc/liuqin-native-root` 标记、清空 `machine-id`、把
  SELinux 改成 permissive；然后写出 `native-root.hashes`（18 万个文件），
  boot.img 里的准入清单要用它。打出来的是一个 `kernel-liuqin` 包，版本形如
  `7.3.0-0.1.g<commit>`（RPM 的 Version/Release 里不能有 `-`，所以拆开写），
  真正的 `uname -r` 记在 `Provides: kernel-uname-r`。装包前会先删掉 Fedora
  自带的 `kernel*` 包和 `/boot` 内容。

## 还没确认的事

- Live ISO 里那个文件仍叫 `LiveOS/squashfs.img`，但从 Fedora 42 起是 EROFS
  （2.34 GB）。按日志确认：**这层 EROFS 解出来就是根**，里面没有
  `LiveOS/rootfs.img`，只有 `boot/`、`usr/` 这些正常目录。脚本已按这个改：
  只认 `LiveOS/rootfs.img` 这个固定位置，没有就把打开的树当根。
- 这棵树里的 `boot/`（515 MiB）和 7.2.11 的内核是用不上的：我们从 `boot_a`
  启动自己的内核，模块也由自己的包提供。第 2 步会把这些连同 Fedora 的内核包
  一起删掉。
- 登录管理器是 **plasmalogin**（`plasma-login-manager` 的一部分），不是
  sddm、也不是 gdm；首次设置的向导是 `plasma-setup.service`，已经在
  `multi-user.target.wants` 里启用了。这些都是 Plasma Mobile 自己的东西，
  不能照搬 Ubuntu 线的 `gnome-initial-setup` / `gdm` 那一套。
- 树里没有 `/etc/fstab`，`/home` 是空的；`/etc/passwd` 里有没有 `liveuser`
  这类现成账户，要等下一次 CI 的报告打出来才知道（报告里会列人类账户和
  自动登录相关文件）。
- GitHub Actions 没有 Fedora 的 runner，也没有 aarch64 的 rpm 系环境，所以
  打包和装包都在 `fedora:45` 的 aarch64 容器里做（runner 本身就是 arm64，
  容器是原生执行，不用模拟）。统一走 `tools/fedora-container.sh`：它钉
  `--platform linux/arm64`，并在容器里再核对一次 `uname -m`，防止拉成 x86 镜像
  在模拟下打包。没有把整个 job 放进 `container:`，因为取根那一步要 loop 挂载、
  要 root、要用 apt 装的 7z/unsquashfs，这些是宿主机（Ubuntu）这一侧的事。
- 内核 RPM 的安装脚本会尝试往 `/boot` 写东西，要绕开。
- 桌面定制（原来的 `device/gnome-overlay`）几乎要重做，工作量最大。

## 怎么跑第 1 步

在 GitHub 上手动触发 `Fedora rootfs` 这个 workflow（只在这个分支上能跑）。
它会把 ISO 下载、解开、写出清单和一份报告，作为 artifact 上传。报告里有树的
大小、包数量、有没有 `plasma-mobile`、`selinux-policy-targeted`、`sddm`。

## hexagonrpcd 的 -R 前缀到底映射什么（读 rpcd_builder.c 得到，2026-11-27）

`construct_root_dir(prefix, dsp)` 把 guest 路径映射到宿主 `<prefix>/` 下：

| guest 看到 | 宿主实际路径 |
|---|---|
| `/vendor/etc/sensors/sns_reg_config` | `<prefix>/sensors/sns_reg.conf` |
| `/vendor/etc/sensors/config/` | `<prefix>/sensors/config/` |
| `/vendor/etc/acdbdata` | `<prefix>/acdbdata` |
| `/persist/sensors/registry/registry`（也挂在 `/mnt/vendor/...`） | `<prefix>/sensors/registry/` |
| `registry/../sns_reg_version`（补丁 0001） | `<prefix>/sensors/sns_reg_version` |
| `/sys/devices/soc0` | `<prefix>/socinfo/` |

所以 `-R /var/lib/liuqin-sensors` 时，目录必须是：

```
/var/lib/liuqin-sensors/sensors/registry/      registry 文件
/var/lib/liuqin-sensors/sensors/sns_reg.conf   缺了会报 Could not open .../sns_reg_config
/var/lib/liuqin-sensors/sensors/sns_reg_version
```

`device/sensors/rom` 里跟踪的就是这些 ROM 文件；装机时要从这里（或 persist）补齐，
不能只搬 registry。
