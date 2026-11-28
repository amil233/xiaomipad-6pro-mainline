# 传感器问题小结（2026-11-28）

## 现象

`monitor-sensor` 停在 `Waiting for iio-sensor-proxy to appear`，重力（加速度计）一直没有，
环境光时有时无。同一台机器、同一个内核，Ubuntu 分支正常。

## 结论

三处问题，都在用户态和装机脚本里，跟内核无关。

### 1. 镜像里根本没有 iio-sensor-proxy 的启动单元（这是"永远 Waiting"的直接原因）

`tools/build-liuqin-sensors-rpm.sh` 在编完 iio-sensor-proxy 之后执行
`rm -rf stage/etc stage/usr/lib/systemd`，把 meson 刚装进去的
`/usr/lib/systemd/system/iio-sensor-proxy.service` 也删了。后来的 commit
`ea54afb`（"let upstream install its own unit"）以为这份单元会留在包里，就把
overlay 里手写的那份也删了，于是两条路都没了。

设备上又卸掉了 Fedora 的 `iio-sensor-proxy` 包（它本来提供这份单元），所以设备上
一个单元都没有。而这个 D-Bus 名字只有两条路能起来，两条都指向那份不存在的单元：

- `device/fedora-overlay/usr/share/dbus-1/system-services/net.hadess.SensorProxy.service`
  里写的是 `Exec=/usr/bin/systemctl start iio-sensor-proxy.service`；
- 上游的 `80-iio-sensor-proxy.rules` 写的是 `SYSTEMD_WANTS+=iio-sensor-proxy.service`。

两处都只会得到 "Unit not found"，`net.hadess.SensorProxy` 永远不会出现在总线上，
这就是 `monitor-sensor` 看到的 Waiting。剩下的
`/etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf` 是一个没有主的
drop-in，不起任何作用。

CI 没抓到，是因为 `tools/verify-unit-references.py` 把 `iio-sensor-proxy.service`
当成"上游包提供"写进了白名单，`tools/verify-liuqin-rpms.sh` 只查了 drop-in 和二进制，
没有查单元本身。

### 2. `sns_reg_version` 被软链覆盖（加速度计注册不出来的原因）

`tools/build-liuqin-fedora-rootfs.sh` 先生成实体文件
`<prefix>/sensors/sns_reg_version`（0644），十几行之后又在一个循环里把它
`ln -sfn` 成 `/var/lib/liuqin-sensors/sns_reg_version`。只有 provision 恰好从
persist 导入了同名文件时这条链才成立，否则是断链。

Ubuntu 分支在这条路径上始终是实体文件（`build-liuqin-native-root.sh` 的 pre-flight
就是按 0644 实体文件检查的）。而固件打开这个文件是 hexagonrpcd 的补丁 0001 特意做的
映射，读不到就打不开 registry 的版本，注册表加载失败，加速度计自然注册不出来。

同一个循环里的 `acc_caldata.txt`、`gyro_caldata.txt`、`Lux_F_channel_data.txt`、
`sensors_list.txt` 其实是无效的：hexagonrpcd 的虚拟文件系统
（`rpcd_builder.c`）在 `/mnt/vendor/persist/sensors/` 下只映射 `registry/` 和
`sns_reg_version` 两项，这四个名字固件根本看不到。所以这次把它们一并去掉，
只保留 `registry -> /var/lib/liuqin-sensors/registry`。

### 3. 样本门禁写成了硬依赖（把"加速度计没好"放大成"连光感都没有"）

`90-liuqin-ssc.conf` 用 `Requires=liuqin-ssc-sample-gate.service`，
gate 只要失败一次，代理就完全不启动，D-Bus 上连名字都不出现。Ubuntu 分支里
gate 只是 target 的 `Wants=`，失败不影响代理启动。

代理对传感器的发现是一次性的（udev 冷插那一刻），所以 gate 先跑完再发现是有意义的，
因此保留 `After=`，只把 `Requires=` 换成 `Wants=`：预热失败时代理照常起来，
环境光仍然可用，加速度计留给下一次事件。

## 改了什么

| 文件 | 改动 |
|---|---|
| `tools/build-liuqin-sensors-rpm.sh` | 不再删 `stage/usr/lib/systemd`，上游单元随包安装 |
| `device/fedora-overlay/etc/systemd/system/iio-sensor-proxy.service.d/90-liuqin-ssc.conf` | `Requires=` → `Wants=`，保留 `After=` |
| `tools/build-liuqin-fedora-rootfs.sh` | 不再软链 `sns_reg_version`，删掉四个无效的校准软链，并断言它是实体文件 |
| `tools/verify-liuqin-rpms.sh` | 增加断言：单元与上游 udev 规则必须在包里 |

## 上机确认（一次刷机就够）

1. 重出 `liuqin-sensors` RPM、重装进树、重装镜像，刷 `boot_a` + `userdata`；
2. 首启后先跑 `provision-liuqin-from-persist.sh /`，输出里应有
   `registry=<三位数>`；没跑过的话 `/var/lib/liuqin-sensors/registry` 是空的，
   固件没有任何注册表可读，加速度计和光感都不会有；
3. 看四件事：

```sh
ls -l /usr/lib/systemd/system/iio-sensor-proxy.service
systemctl status liuqin-slpi liuqin-hexagonrpcd-sdsp liuqin-ssc-sample-gate --no-pager
busctl --system tree net.hadess.SensorProxy | head
monitor-sensor
```

- 单元存在、`liuqin-hexagonrpcd-sdsp` 是 active、`monitor-sensor` 报出
  `Accelerometer orientation changed` 与 `Light changed` → 通了；
- 单元存在但代理仍不出现：看 `journalctl -u iio-sensor-proxy -b`，
  此时大概率是 D-Bus 激活或 polkit 的问题，与本次三处改动无关；
- 代理出现但 `HasAccelerometer=false`：问题在固件侧（registry 或
  `sns_reg_version`），看 `journalctl -u liuqin-hexagonrpcd-sdsp -b` 里有没有
  `Could not open /../sns_reg_version`。
