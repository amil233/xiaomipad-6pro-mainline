# 状态（2026-11-26，Fedora 分支）

这条分支做的是把平板从 Ubuntu + GNOME 换成 Fedora 45 KDE Plasma Mobile。**还没在
真机上启动过**，下面分开写"CI 上已经产出的"和"还没验证的"。

会变的数字（内核版本、镜像哈希）不写死，用命令现场查。

## 已经跑通的（都在 CI 上）

| 项 | 现状 |
|---|---|
| 取自 Live ISO 的根 | Fedora 45 KDE Mobile，ext4（ISO 里那层是 EROFS，解开就是根）；131,266 个文件、1713 个包、6107 MiB |
| 内核包 | `kernel-liuqin` RPM 装进树：756 个模块，树降到 5377 MiB（Fedora 自带内核和 `/boot` 已清掉） |
| 根整理 | marker、`machine-id` 清空、SELinux permissive，`native-root.hashes` 已生成 |
| 桌面 | `plasma-mobile 6.8.1`、`plasma-workspace 6.8.1`、`plasma-setup 6.8.1`、登录管理器 `plasmalogin` |
| 整条流水线 | 一次跑通（16 分 44 秒）：boot.img 192 MiB、ext4 镜像 7,584,350,208 字节（约 7.06 GiB）、`rootfs.tgz` 约 2.25 GiB、切成 2 片（1.9 GiB + 352 MiB） |
| 版本钉住 | boot.img 里 `expected_release=7.3.0-gb746af962d0c`，与树里的 `kernel.release` 一致 |

## 真机上已经验证的（2026-11-27，第一次刷机）

| 项 | 结果 |
|---|---|
| 启动 | 刷 `boot_a` + `userdata` 后进到 **plasma-setup** 的建用户界面，说明准入、initramfs、systemd、显示都过了 |
| 根分区 | `resize2fs /dev/disk/by-partlabel/userdata` 正常，`df -h` 显示 `/dev/sda36` 105 GiB |
| 包管理 | `dnf upgrade` 可用（Fedora 仓库能连上、能装） |
| Wi-Fi | **没跑 `provision-liuqin-from-persist.sh` 就已经可用** |

Wi-Fi 能用但不代表地址是稳定的。接口名是 `wlp1s0`（systemd 的可预测命名），
persist 里的文件写的却是 `wlan0=...`。

**已经确认（2026-11-27）：MAC 重启后不变**，所以地址这套可以往后放——路由器看到的
是同一台设备，静态 DHCP、租约、MAC 白名单都稳定。只是和机身上印的不一致，没有实际
影响。等真正需要（比如要设备树里写死地址）再回来做。

原先的担心是：ath11k 在没有从设备树或 persist 拿到本机地址时，用的是驱动自己生成的
地址，如果每次启动都变就会破坏上面那些东西：

```sh
ip link show wlp1s0 | grep ether     # 记下地址，重启，再看一次
```

- 每次一样：只是和原厂地址不同，网络身份稳定，这件事可以往后放；
- 每次不一样：路由器每次发新租约、静态 DHCP/端口转发/家长控制都会失效，企业 Wi-Fi
  和需要 MAC 白名单的网络每次都要重新认证，同一网段里还会留下大量过期租约。这时候
  才值得把 persist 的地址写进去。

## 还没验证的

| 项 | 状态 | 说明 |
|---|---|---|
| 真机启动 | 未验证 | 一次都没刷过；这是下一步 |
| 显示 / 触控 | 未验证 | 依赖主线内核 + Mesa，与 Ubuntu 线同一套驱动 |
| Wi-Fi / 蓝牙 | 未验证 | 地址来自 persist，需要跑 `provision-liuqin-from-persist.sh` |
| 音频 | 未验证 | 拓扑和 UCM2 的移植还没做，KDE 侧走 PipeWire |
| 传感器 / 电源键 / 指纹 / 相机 | 未验证 | Ubuntu 线那套设备载荷还没移植成 RPM |
| 首次设置 | 未验证 | 应当进 plasma-setup 建用户 |

## 已知问题 / 待办

| 项 | 现状 |
|---|---|
| 设备载荷没移植 | 固件和 UCM2 已经打成 `liuqin-device` 装进去了；传感器栈、电源键、指纹还没 |
| 下一步：传感器栈 | 需要移植三样东西：`hexagonrpcd`（SLPI 上的传感器服务端）、SSC registry 文件（`provision-liuqin-from-persist.sh` 已经能导入，等 `fastrpc` 账户存在时生效）、`iio-sensor-proxy`（Fedora 有包，但 Ubuntu 线替换过一份，要先确认 Fedora 版认不认 `/var/lib/liuqin-sensors/registry` 这套布局）。另外要新增 `fastrpc` 用户和 `/etc/udev/rules.d/80-liuqin-fastrpc.rules` 那套权限 |
| SELinux | 先 permissive；策略和标签没打全之前不收紧 |
| 自动登录 | `etc/plasmalogin.conf` 里有 autologin 相关配置，树里没有人类账户，第一次启动走 plasma-setup，上机时确认 |
| 自动锁屏后触摸失效 | 开着自动锁屏、长时间无操作后熄屏，再唤醒时系统活着（长按电源能弹出登录框）但触摸没有事件。**关闭自动锁屏后不再触发**，属于体验问题，暂不阻塞；根因未定位（怀疑是挂起/恢复时触摸驱动的恢复顺序，见驱动里 `nvt_ts_resume` 对面板就绪的依赖）。要用时要能输入，先 `sudo systemctl mask sleep.target suspend.target` 或关掉自动锁屏 |
| 无 `/etc/fstab` | 根由 initramfs 挂好，systemd 不需要 fstab；确认没有服务因此报错 |
| 内核升代 | 现在跟主线 7.3；Fedora 45 自带的也是 7.3.6，同代 |

## 文档

| 文档 | 内容 |
|---|---|
| [`FEDORA.zh-CN.md`](FEDORA.zh-CN.md) | 换发行版的来龙去脉、五个阶段、还没确认的事 |
| [`BUILD.zh-CN.md`](BUILD.zh-CN.md) | 从 ISO 到可刷产物 |
| [`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) | 刷机、更新、回滚 |
| [`RESCUE.zh-CN.md`](RESCUE.zh-CN.md) | initramfs 救援 shell、救援 boot.img 的生成 |
| [`archive/`](archive/) | 历史记录，不再维护 |
