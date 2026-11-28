# 传感器问题小结（2026-11-28）

## 现象

`monitor-sensor` 停在 `Waiting for iio-sensor-proxy to appear`，重力（加速度计）一直没有，
环境光时有时无。同一台机器、同一个内核，Ubuntu 分支和参考项目
（`yzddmr6/xiaomipad-6pro-mainline`，Ubuntu 26.04）都正常。

## 为什么不是固件

固件是固定的：参考项目喂给它的文件和我们喂的不一样，差别在"喂什么"这一侧，不在
固件。参考项目的 `tools/build-liuqin-sensors-stack.sh` 里，`sns_reg_version` 是
`printf` 写出来的**实体文件**，还算并钉了 SHA-256；我们这条分支把它软链到了 `/var`。

## 一、Fedora 有 iio-sensor-proxy 包，而且本来就该用它

查到的包内容（`iio-sensor-proxy-3.8-1.fc43`，rawhide 的 spec 是 3.9）：

| 文件 | 作用 |
|---|---|
| `/usr/lib/systemd/system/iio-sensor-proxy.service` | 定义 `net.hadess.SensorProxy` 这个 D-Bus 名字 |
| `/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules` | 把 `/dev/fastrpc-sdsp` 标成 SSC 传感器，并要求启动代理 |
| `/usr/share/dbus-1/system.d/net.hadess.SensorProxy.conf` | 允许 root 拥有这个名字 |
| `/usr/share/polkit-1/actions/net.hadess.SensorProxy.policy` | claim-sensor 的动作定义 |
| `/usr/libexec/iio-sensor-proxy`、`/usr/bin/monitor-sensor` | 发行版编的二进制 |

**它没有** `/usr/share/dbus-1/system-services/net.hadess.SensorProxy.service`（D-Bus 激活
条目），这一条必须由我们带，否则第一个调用者拉不起代理。

参考项目在 Ubuntu 上就是"留发行包、只换二进制"：它把上游 meson 装进层里的单元、
udev 规则、bus 策略、polkit 策略**删掉**，注释写的是 *"Ubuntu owns the 3.8 SensorProxy
binary/unit/data paths"*，然后只把打过补丁的二进制装到
`/usr/local/libexec/liuqin-iio-sensor-proxy`，用 drop-in 改 `ExecStart`。

我们这条分支做了相反的事：装自己的包之前先 `rpm -e` 掉 Fedora 的 `iio-sensor-proxy`，
自己重写这四份文件——然后构建脚本里一句
`rm -rf "$out_dir/stage/etc" "$out_dir/stage/usr/lib/systemd"` 把单元删了，
`ea54afb` 又把手写的那份删了。设备上一个单元都没有，两条启动路径都指向它：

- D-Bus 激活：`Exec=/usr/bin/systemctl start iio-sensor-proxy.service`；
- udev 规则：`SYSTEMD_WANTS+=iio-sensor-proxy.service`。

都只会得到 "Unit not found"，`monitor-sensor` 就永远等。

**改法**：回到参考项目的分工。发行包继续装着，负责单元、udev 规则、bus/polkit 策略和
`monitor-sensor`；我们的包只提供 `/usr/local/libexec/liuqin-iio-sensor-proxy` 和
D-Bus 激活条目，drop-in 里 `ExecStart=` 指过去（顺带写一遍
`RestrictAddressFamilies=AF_QIPCRTR`，发行包若是 3.8 的单元没有这一项）。
这样我们自己漏装一份也不会再让整条链断掉，发行包升级还能把单元一起带上来。

## 二、`sns_reg_version` 被软链覆盖（加速度计注册不出来）

`tools/build-liuqin-fedora-rootfs.sh` 先生成实体文件
`<prefix>/sensors/sns_reg_version`（0644），十几行之后又把它
`ln -sfn` 成 `/var/lib/liuqin-sensors/sns_reg_version`。只有 provision 恰好从 persist
导入了同名文件时这条链才成立，否则是断链。固件读这个文件是 hexagonrpcd 补丁 0001
特意加的映射，读不到就打不开 registry 的版本。

同一个循环里的 `acc_caldata.txt`、`gyro_caldata.txt`、`Lux_F_channel_data.txt`、
`sensors_list.txt` 是无效的：hexagonrpcd 的虚拟文件系统（`rpcd_builder.c`）在
`/mnt/vendor/persist/sensors/` 下只映射 `registry/` 和 `sns_reg_version` 两项。
已去掉。

## 三、少了参考项目为环境光补的三份补丁（"光感时有时无"）

参考项目比它自己那套 Ubuntu 线多带三份 `iio-sensor-proxy` 补丁（来自
`yzddmr6/xiaomipad-8pro-mainline`，作者信息原样保留）：

| 补丁 | 修什么 |
|---|---|
| 0008 串行化 SSC 环境光轮询 | libssc 的同步调用会派发主循环，ClaimLight/ReleaseLight 在打开没完成时到达会把流关掉；加速度计早就有同类补丁（0004） |
| 0009 报告环境光发现错误 | 失败时留下原因，不再静默 |
| 0010 关闭驱动前摘掉回调 | 客户端消失时重入已释放的表（会话重启时的崩溃） |

## 四、运行库：另一处发行版差异

libssc 运行时链 `libqmi-glib`、`libqrtr-glib`、`libprotobuf-c`，分别来自 Fedora 的
`libqmi`、`libqrtr-glib`、`protobuf-c` 包。这三份**不是** `iio-sensor-proxy` 包的依赖，
KDE Mobile 的包集里不一定有；缺任何一个，`ssccli` 和代理都会在动态链接阶段就退出，
表现同样是 gate 失败、代理不出现。`install` 后的检查已经把这三个包列为必须存在。

## 改了什么

| 文件 | 改动 |
|---|---|
| `tools/build-liuqin-sensors-rpm.sh` | 不再卸 Fedora 的包；只装 `/usr/local` 下的二进制和激活条目；`install` 时确认发行包与三个运行库在树里；补丁集扩到 0008–0010 |
| `device/fedora-overlay/etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf` | 加 `ExecStart=` 覆盖与 `AF_QIPCRTR`；`Requires=` 与参考项目一致 |
| `tools/build-liuqin-fedora-rootfs.sh` | 不再软链 `sns_reg_version`，删掉四个无效软链，断言它是实体文件 |
| `device/sensors/patches/0008..0010` | 从参考项目导入，作者与说明原样保留 |
| `tools/verify-liuqin-rpms.sh` | 断言我们的包不含发行包的任何路径（避免两个包抢文件） |

## 上机确认（一次刷机就够）

1. 重出 `liuqin-sensors` RPM、重装进树、重装镜像，刷 `boot_a` + `userdata`；
2. 首启后跑 `provision-liuqin-from-persist.sh /`，输出里应有 `registry=<三位数>`；
3. 依次看：

```sh
rpm -q iio-sensor-proxy
ls -l /usr/local/libexec/liuqin-iio-sensor-proxy
systemctl status liuqin-slpi liuqin-hexagonrpcd-sdsp liuqin-ssc-sample-gate --no-pager
cat /run/liuqin-sensors/accelerometer-ready
busctl --system tree net.hadess.SensorProxy | head
monitor-sensor
```

判据：

- `iio-sensor-proxy` 包不在 → 树里少了发行包，`install` 会直接失败，不会到设备上才发现；
- 代理不在、gate 是 failed → 看 `/run/liuqin-sensors/ssccli-accelerometer.log`，
  这时问题在 ssccli 与固件之间（registry、节点权限、hexagonrpcd 日志）；
- 代理出现、`HasAccelerometer=true`、`monitor-sensor` 能报方向 → 这条链通了；
- 代理正常但桌面不旋转 → 是 KDE 侧读取代理的那一环（参考项目那两个 refresh 单元是
  GNOME 专用的，不能照搬），另查。
