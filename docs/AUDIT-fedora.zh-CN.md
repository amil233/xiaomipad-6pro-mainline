# Fedora 线：每个文件、每处改动，以及为什么这么做

本文按"文件"组织。每条都写明依据，依据只有三类：**源码**（工作区内的内核或组件
源码）、**对照样本**（Ubuntu 分支已验证可运行的实现）、**硬约束**（发行版或工具
本身的规则）。不写"我觉得"。

## 一、新增脚本

### `tools/fedora-container.sh`

**做什么**：把一条命令放进 `fedora:45` 容器执行，挂载项目到 `/work`，先装需要的包。

**为什么**：runner 是 Ubuntu aarch64，没有 rpmbuild/dnf/rpm；GitHub 也没有 arm64 的
Fedora runner。容器是原生 aarch64，不是模拟。`--platform` 与容器内 `uname -m` 双重
校验，是因为镜像仓库同时提供 x86_64，拉错会在 qemu 下打包，速度与结果都不可信。

### `tools/build-liuqin-fedora-base.sh`

**做什么**：下载 Live ISO、按官方 `CHECKSUM` 校验、抽出 `LiveOS/squashfs.img`、按魔数
判断格式（squashfs / EROFS / ext4）、挂载里面的根、复制整棵树（保留属主、ACL、
SELinux 标签）、报告。

**为什么**：Fedora 42 起 Live 媒体用 EROFS 但文件名仍叫 `squashfs.img`（Fedora wiki
`Changes/EROFSforLiveMedia`），所以格式必须按魔数判断，不能按文件名。根必须是 ext4，
因为我们的 initramfs 只按 ext4 挂载并做哈希/版本校验。报告里记录包数量、SELinux
状态、`/boot` 体积，是后续决定"删不删自带内核"的依据。

### `tools/build-liuqin-kernel-rpm.sh`

**做什么**：把内核 CI 产物打成一个 `kernel-liuqin` RPM，装进树；装之前先卸掉 Fedora
自带的 `kernel*`。

**为什么**：RPM 的 `Version`/`Release` 不允许 `-`，而我们的 `uname -r` 形如
`7.3.0-g<sha>`，所以拆成 `7.3.0` + `0.1.g<sha>`，真实版本用
`Provides: kernel-uname-r` 记着。卸载 Fedora 内核用 `--noscripts`：那些包的脚本会写
`/boot`、调 `kernel-install`/`dracut`，在离线装配的树里没有意义。载荷只含模块和
`/usr/share/liuqin/kernel.release`，因为内核镜像走 `boot.img`。

### `tools/build-liuqin-device-rpm.sh`

**做什么**：打包"文件型"设备数据——`device/firmware`、WLAN board tuple、ALSA UCM2、
静态 busybox、救援通道脚本与单元、`fastrpc` 的 udev 规则。

**为什么**：这些是纯文件，和桌面无关。UCM2 放这里是因为它是 ALSA 配置，KDE 与 GNOME
共用；救援通道（`liuqin-rescue`/`liuqin-usb-rescue` + busybox）与发行版无关，
`usb0` 是 initramfs 建好的 gadget。没有搬 `gnome-overlay` 的其余部分，因为 Plasma
Mobile 自带电源菜单、亮度与虚拟键盘，GNOME 那套定制在这里没有对应物。

### `tools/build-liuqin-fedora-rootfs.sh`

**做什么**：整理树——写 `/etc/liuqin-native-root`、清空 `machine-id`、SELinux 改
permissive、离线创建 `fastrpc` 账户、铺传感器 ROM 数据与软链、写 `native-root.hashes`。

**为什么**（逐项）：

- marker：initramfs 靠它认根；
- `machine-id` 留空：systemd 首启生成，避免镜像里带一个固定 id；
- permissive：我们的树是离线装配的，`:security.selinux` 标签不一定全对，enforcing 会
  让服务起不来；
- `fastrpc` 账户离线建：`provision` 要按名字查 uid；RPM 的 `%pre` 我们用
  `--noscripts` 跳过；
- 传感器数据布局：`hexagonrpcd --help` 写明 `-R` 默认 `/usr/share/qcom/`，`rpcd.c`
  里按 `{soc}/{vendor}/{codename}` 自动探测；`rpcd_builder.c` 的
  `construct_root_dir` 把 guest 的 `/vendor/etc/sensors/*`、`/persist/sensors/registry/*`、
  `/sys/devices/soc0/*` 映射到 `<prefix>/sensors/*`、`<prefix>/socinfo`；Ubuntu 分支的
  构建脚本正是这么装的（`device_prefix=usr/share/qcom/sm8450/Xiaomi/liuqin`）；
- `sns_reg_version`：Ubuntu 脚本用 `printf 'version=%s\0'` 从 `sns_reg_config` 的
  `version=` 生成，位置在 `<prefix>/sensors/`；缺它时 daemon 日志里反复出现
  `Could not open /../sns_reg_version`；
- `registry` 软链到 `/var`：固件要在 registry 旁写 `temp.json`，只读树不行；
- `socinfo` 软链到 `/sys/devices/soc0`：值由内核 `qcom_socinfo` 提供，复制会过期。

### `tools/build-liuqin-fedora-boot.sh`（由 `build-liuqin-native-boot.sh` 改名）

**做什么**：用内核产物 + ABL overlay + 新 initramfs 组成 `boot.img`，补零到 192 MiB。

**为什么**：Ubuntu 线的 `boot.img` 里带"rootfs 文件清单"，本分支改成钉内核版本：
`EXPECTED_RELEASE` 写进 initramfs，启动时和根里的 `kernel.release` 比较。理由是本分支
的根来自 Fedora 发行版树，逐文件清单没有维护价值，而"内核与模块同源"是真正要守住的
不变量。

### `tools/build-liuqin-fedora-image.sh`

**做什么**：把树做成 ext4（`LABEL=LIUQIN_ROOT`，树在 `native-root/` 下），过
`e2fsck`、卷标与 `debugfs` 检查，出 `SHA256SUMS`。

**为什么**：原厂分区表里 `userdata` 是唯一数据分区，initramfs 按 `LABEL` 找根并把
`native-root/` 当 `/`。镜像只做"树 + 25%"，因为平板首启后可以 `resize2fs` 长满分区。

### `tools/build-liuqin-sensors-rpm.sh`

**做什么**：按 `device/sensors/sources.manifest` 取三个源码，打 2 + 6 份补丁，在
`fedora:45` 里编，打成 `liuqin-sensors`，替换 Fedora 的 `iio-sensor-proxy`。

**为什么**：

- 组件顺序 `hexagonrpc → libssc → iio-sensor-proxy`：Ubuntu 脚本同样顺序，因为只有
  `iio-sensor-proxy` 需要 `libssc`；
- `libssc` 装两遍：一遍进容器 `/usr`（`.pc` 里 prefix 是 `/usr`，编译期要真实存在），
  一遍进 staging（作为载荷）；
- 文件清单从 staging 生成：上游的单元名、udev 规则名、soname 会随版本变，手写必然
  过期（已经踩过 `iio-sensor-proxy.service` 名字不符的坑）；
- 不打包 man/doc、删掉 libssc 的 python mocking 服务器：两者都会被 rpmbuild 的后处理
  改写（`.gz`、`.pyc`），变成"装进 buildroot 但不在清单里"的文件；
- 安装前卸掉 Fedora 的 `iio-sensor-proxy`：文件冲突，且设备上只能有一份，
  必须是打过补丁的那份。

### `tools/lib/rootfs-manifest.sh`

**做什么**：一次 `find` 取元数据、一次 `xargs sha256sum` 取哈希、python 合成为清单。

**为什么**：旧写法对每个文件 fork 一次 `sha256sum`，13 万文件约 6 分钟，是 Report 步骤
慢的全部原因；批量后本机实测 1203 个文件 0.10 秒。

## 二、改动的共享文件

### `initramfs/init`

**改了什么**：删掉 GNOME/旧契约/native 三套准入，改成一套：marker、systemd 可执行、
`ID=fedora`、根的 `kernel.release` 等于 initramfs 里钉的值、对应 `modules.dep` 在。

**为什么**：本分支只启动一种发行版；保留三套准入只会让"哪套规则在生效"变含糊。版本
比对取代原来的文件清单，正好承担"boot.img 与 rootfs 必须一起刷"这条规则。

### `tools/lib/build-initramfs.sh`

**改了什么**：删除契约校验与契约文件、`gnome`/`native` 分支；只接受
`LIUQIN_ROOT_PROFILE=fedora`；新增必填 `EXPECTED_RELEASE` 写入
`/etc/liuqin-expected-release`。

**为什么**：同上——准入机制跟着 init 一起简化；`EXPECTED_RELEASE` 是 init 比对所需的
唯一输入。

### `device/sensors/patches/0002-*.patch`

**改了什么**：删掉属性白名单（连同它的三个字符串、门禁分支、以及补丁里自带的测试
文件与 `tests/meson.build` 改动）。

**为什么**：门禁之后的实现只是清零并返回空串（`sns_registry.c` 补丁正文），它没有
代理任何宿主属性，因此白名单不提供安全收益，只会在名字不匹配时丢掉传感器（设备上
一次启动 54 次拒绝）。补丁里自带测试文件还需要跟着维护 `main`，删掉后补丁只触碰
`hexagonrpcd/`。

### `device/configs/liuqin-fedora.config` + `kernel/source.json`

**为什么**：arm64 默认配置里没有 SELinux，而 Fedora 的 systemd 与服务假定它存在；
`source.json` 把分支指向 `liuqin-7.3-fedora` 并把这个碎片加进列表。

### `.github/workflows/fedora-rootfs.yml`

**为什么这样组织**：一条 job 是因为 6 GiB 的树放在 runner 本地，不需要用 artifact
在两个 job 之间搬运；取根与镜像装配需要 loop 挂载和 root，留在宿主机；RPM 相关全部
进容器。产物统一进 `project/out/artifact` 并打成 7z 固实分卷，因为 7-Zip 能直接打开
第一卷、且 LZMA2 比 gzip 压得更小（1.71 GB 对 2.25 GiB）。

## 三、`device/fedora-overlay` 里的每个文件

| 文件 | 为什么需要 |
|---|---|
| `etc/udev/rules.d/80-liuqin-fastrpc.rules` | 设备是 `misc_register("fastrpc-<domain>")`（`fastrpc.c:2468`），默认 `root:root 0600`；规则同时给出 `IIO_SENSOR_PROXY_TYPE="ssc-accel"`（`drv-ssc-accel.c` 靠它识别加速度计）、`SYSTEMD_WANTS=liuqin-sensor-stack.target`（设备事件启动整条栈）和 `ACCEL_MOUNT_MATRIX`（横屏 180°） |
| `etc/systemd/system/liuqin-slpi.service` | SLPI 不自动启动，需要用户态 `start`；这是唯一开机启用的传感器单元 |
| `usr/local/sbin/liuqin-slpi` | 写 `remoteproc` 的 `state`，并在 registry 未导入时只告警 |
| `etc/systemd/system/liuqin-hexagonrpcd-sdsp.service` | `Requires=liuqin-slpi`（节点后出现）+ `ConditionPathExists=/dev/fastrpc-sdsp` + `ExecStartPre` 兜底权限 |
| `etc/systemd/system/liuqin-sensor-stack.target` | udev `SYSTEMD_WANTS` 的目标 |
| `etc/systemd/system/liuqin-ssc-sample-gate.service` + `usr/libexec/liuqin-ssc-sample-gate` | 加速度计必须先被 claim 一次才注册（`drv-ssc-accel.c` 用 open/close 发现），gate 用 `ssccli` 取真实测量，成功才允许发布 SensorProxy |
| `etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf` | `Requires` gate；放开 `AF_QIPCRTR`，libssc 走 QMI over QRTR |
| `etc/polkit-1/rules.d/49-liuqin-sensorproxy.rules` | 上游默认 `allow_active` 会和登录时的 session 注册竞争，导致整个 boot 拿不到方向；Ubuntu 线为此加了同样规则 |
| `etc/sysusers.d/liuqin-fastrpc.conf`、`etc/tmpfiles.d/liuqin-sensors.conf` | 账户与目录的声明式来源（Ubuntu 线原本如此），`assemble` 的离线建号与之兼容 |
| `usr/local/sbin/liuqin-sensor-registry-import` | 手工重导 registry 的操作工具，带校验和与旧目录备份 |
| `usr/local/bin/busybox`、`liuqin-shell`、`usr/local/sbin/liuqin-rescue`、`liuqin-usb-rescue`、`etc/systemd/system/liuqin-usb-rescue.service` | USB telnet 维护通道；`usb0` 由 initramfs 的 gadget 留下，本单元只做地址、`udhcpd`、`telnetd`；默认不启用（`ConditionPathExists=/etc/liuqin-rescue-enabled`） |
| `usr/share/dbus-1/system-services/net.hadess.SensorProxy.service` | 上游 meson 不装 D-Bus 激活条目，而 Fedora 的 RPM 提供它；我们替换了那个包，所以要自带 |

## 四、删除的文件及理由

`build-liuqin-{boot,rootfs,debs,native-root,rootfs-image,settings,ubuntu-desktop-rootfs,rescue-boot}.sh`、
`build-liuqin-image.py`、`prepare-image-inputs.py`、`build-root-contract.py`、Ubuntu 的
`rootfs.yml`、以及对应的 7 个测试：它们是 Ubuntu + deb + GNOME 的装配链，本分支不再
使用。留着会让"哪套布局与准入是对的"无法判断——这次多处错误正是因为照着旧脚本的
片段改，而没有对照正在运行的那一支。

## 五、仍然没有证据的三项（不写"应该没问题"）

1. `fastrpc` 账户号取 201–999 第一个空位：依据是 Fedora 的 `setup` 包把
   `SYS_UID_MIN` 设为 201、`SYS_UID_MAX` 设为 999，但这条我没有在本机核对过 Fedora 的
   `login.defs`；
2. `sns_reg_version` 的 NUL 结尾：照 Ubuntu 脚本的 `printf 'version=%s\0'` 复制的，
   语义（固件如何解析）未从固件侧确认；
3. 清空 `/boot`、移除 Fedora `kernel*` 包后 `dnf upgrade` 的行为：没有核对过 Fedora
   的依赖关系。

这三项都可以在没有平板的情况下核对（读 Fedora 的 `setup`/`dnf` 元数据），属于下一步。
