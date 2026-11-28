# 传感器问题小结（2026-11-28）

## 现象

`monitor-sensor` 停在 `Waiting for iio-sensor-proxy to appear`，重力（加速度计）一直没有，
环境光时有时无。同一台机器、同一个内核，Ubuntu 分支和参考项目
（`yzddmr6/xiaomipad-6pro-mainline`，Ubuntu 26.04）都正常。

## 这份结论的证据等级

写清楚哪些是查过的、哪些是推出来的，免得把推断当成事实用。

| 结论 | 来源 | 等级 |
|---|---|---|
| Fedora 45 的 `iio-sensor-proxy` 包含单元/udev/bus/polkit 策略和 `monitor-sensor`，不含 D-Bus 激活条目 | 包的 `%files`（`packages.fedoraproject.org`）与 [spec](https://src.fedoraproject.org/rpms/iio-sensor-proxy) | 一手 |
| Debian/Ubuntu 的包是**同一组六份文件**，同样没有激活条目 | `packages.debian.org` 的 arm64 文件清单 | 一手 |
| Debian 在 arm64 上用 `-Dssc-support=enabled` 编，Fedora 是 `disabled` | Debian `debian/rules`；Fedora spec | 一手 |
| Fedora 的 `qt6-qtsensors` 带 `libqtsensors_iio-sensor-proxy.so`，KDE 侧能读这个代理 | Fedora 45 包文件清单 | 一手 |
| 我们的构建把单元删了、发行包又被 `rpm -e` | 仓库里的 `build-liuqin-sensors-rpm.sh` 与提交历史 | 一手 |
| `-R` 不写时 daemon 会去找 `sm8475`，而树在 `sm8450` | `rpcd.c` 的 `guess_device_directory_from_compatible()` + 解析 boot.img 里合并后的 DTB 得到的 root 属性 | 一手（算法与输入都查了） |
| 于是固件读不到 registry，一个传感器都不注册 | 严格映射（`hfs_map`）会对缺失路径返回 `ENOENT`；DSP 侧怎么处理是闭源的 | **推断** |
| 缺 `sns_reg_version` 会让 registry 加载失败 | 同上，另外参考项目从不缺这个文件 | **推断** |
| 三份环境光补丁能治"光感时有时无" | 来自跑通的参考项目，补丁主题对应得上 | **移植，因果未证** |

还有一处观察和推断不一致，必须留着：**如果光感在没有 `-R` 的镜像上真的偶尔能用**，
那说明当时 registry 路径是通的，`-R` 这条结论就要重判（见最后一节的判定方法）。

## 为什么不是固件

固件是固定的：参考项目喂给它的文件和我们的不一样，差别在"喂什么"这一侧，不在
固件。参考项目的 `tools/build-liuqin-sensors-stack.sh` 里，`sns_reg_version` 是
`printf` 写出来的**实体文件**，还算并钉了 SHA-256；我们这条分支把它软链到了 `/var`。

## 一、Fedora 有 iio-sensor-proxy 包，而且本来就该用它（Waiting 的直接原因）

查到的包内容（`iio-sensor-proxy-3.9-3.fc45`）：

| 文件 | 作用 |
|---|---|
| `/usr/lib/systemd/system/iio-sensor-proxy.service` | 定义 `net.hadess.SensorProxy` 这个 D-Bus 名字 |
| `/usr/lib/udev/rules.d/80-iio-sensor-proxy.rules` | 把 `/dev/fastrpc-sdsp` 标成 SSC 传感器，并要求启动代理 |
| `/usr/share/dbus-1/system.d/net.hadess.SensorProxy.conf` | 允许 root 拥有这个名字 |
| `/usr/share/polkit-1/actions/net.hadess.SensorProxy.policy` | claim-sensor 的动作定义 |
| `/usr/libexec/iio-sensor-proxy`、`/usr/bin/monitor-sensor` | 发行版编的二进制 |

对照 Debian/Ubuntu 的同一个包（`packages.debian.org` 的 arm64 文件清单）：**两边是同一组
六份文件，也都同样没有** `/usr/share/dbus-1/system-services/` 激活条目。代理在两边都是
靠 udev 规则在 `/dev/fastrpc-sdsp` 出现时用 `SYSTEMD_WANTS` 拉起来的，Ubuntu 上跑通的
就是这条路径。所以激活条目不是必需件，我们此前自带的那一份已经删掉。

真正需要我们自己编二进制的是另一处差异：Debian 的 `debian/rules` 在 arm64 上
`-Dssc-support=enabled`（`ARCHES_QCOM_SSC = arm64`），Fedora 的 spec 是
`-Dssc-support=disabled`。所以 Ubuntu 的发行版二进制本来就能看 SSC（参考项目换它是为了
那几个补丁），而 Fedora 的必须换。

参考项目在 Ubuntu 上就是"留发行包、只换二进制"：它把上游 meson 装进层里的单元、
udev 规则、bus 策略、polkit 策略**删掉**，注释写的是 *"Ubuntu owns the 3.8 SensorProxy
binary/unit/data paths"*，然后只把打过补丁的二进制装到 `/usr/local/libexec/`，用
drop-in 改 `ExecStart`。

我们这条分支做了相反的事：装自己的包之前先 `rpm -e` 掉 Fedora 的 `iio-sensor-proxy`，
自己重写这四份文件——然后构建脚本里一句
`rm -rf "$out_dir/stage/etc" "$out_dir/stage/usr/lib/systemd"` 把单元删了，
`ea54afb` 又把手写的那份删了。设备上一个单元都没有，两条启动路径都指向它：

- D-Bus 激活：`Exec=/usr/bin/systemctl start iio-sensor-proxy.service`；
- udev 规则：`SYSTEMD_WANTS+=iio-sensor-proxy.service`。

都只会得到 "Unit not found"，`monitor-sensor` 就永远等。

**改法**：回到参考项目的分工。发行包继续装着，负责单元、udev 规则、bus/polkit 策略和
`monitor-sensor`；我们的包只提供 `/usr/libexec/liuqin-iio-sensor-proxy` 这一个二进制，
drop-in 里 `ExecStart=` 指过去，并写一遍 `RestrictAddressFamilies=AF_QIPCRTR`
（发行包若是 3.8 的单元没有这一项）。这样我们自己漏装一份也不会再让整条链断掉，
发行包升级还能把单元一起带上来。

## 二、hexagonrpcd 找不到注册表目录（重力一直出不来的原因）

`hexagonrpcd` 的前缀（`-R`）决定它把哪些宿主文件当成固件的 `/vendor/etc/sensors`、
`/mnt/vendor/persist/sensors`。Ubuntu 线写死
`-R /usr/share/qcom/sm8450/Xiaomi/liuqin`；Fedora 分支某次提交把它去掉了，理由写的是
"用 daemon 自己的默认布局"。

默认布局确实是 `/usr/share/qcom/{soc}/{vendor}/{codename}`，但目录名是 daemon 按设备树
**猜**出来的（`rpcd.c` 的 `guess_device_directory_from_compatible()`）：

- `model = "Xiaomi Pad 6 Pro"` → 厂商取第一个空格前 → `Xiaomi`；
- `compatible = "xiaomi,liuqin", "qcom,sm8475"` → SoC 取第一个 `qcom,` 前缀 → `sm8475`；
- 于是它去找 `/usr/share/qcom/sm8475/Xiaomi/liuqin`，而树装在原厂 vendor 分区命名的
  `/usr/share/qcom/sm8450/Xiaomi/liuqin`。两个候选目录都不存在，函数返回 NULL，
  daemon 退回默认前缀 `/usr/share/qcom/`——那里没有 `sensors/`，固件读不到
  `sns_reg.conf` 和 registry，一个传感器都不会注册。

这不是"固件不认"，是我们交给它的前缀是空的。**改法**：`-R` 写死成和树一致
（和 Ubuntu 线一致），并在 CI 里断言单元里的路径等于树里实际安装的路径。

## 三、`sns_reg_version` 被软链覆盖

`tools/build-liuqin-fedora-rootfs.sh` 先生成实体文件
`<prefix>/sensors/sns_reg_version`（0644），十几行之后又把它
`ln -sfn` 成 `/var/lib/liuqin-sensors/sns_reg_version`。只有 provision 恰好从 persist
导入了同名文件时这条链才成立，否则是断链。固件读这个文件是 hexagonrpcd 补丁 0001
特意加的映射。

同一个循环里的 `acc_caldata.txt`、`gyro_caldata.txt`、`Lux_F_channel_data.txt`、
`sensors_list.txt` 是无效的：hexagonrpcd 的虚拟文件系统（`rpcd_builder.c`）在
`/mnt/vendor/persist/sensors/` 下只映射 `registry/` 和 `sns_reg_version` 两项。
已去掉。

## 四、少了参考项目为环境光补的三份补丁（"光感时有时无"）

参考项目比它自己那套 Ubuntu 线多带三份 `iio-sensor-proxy` 补丁（来自
`yzddmr6/xiaomipad-8pro-mainline`，作者信息原样保留）：0008 串行化 SSC 环境光轮询、
0009 报告环境光发现错误、0010 关闭驱动前摘掉回调。加速度计早就有同类补丁（0004），
环境光一直没有。

## 五、运行库（现在由 CI 判定）

libssc 运行时链 `libqmi-glib`、`libqrtr-glib`、`libprotobuf-c`，分别来自 Fedora 的
`libqmi`、`libqrtr-glib`、`protobuf-c` 包。这三份**不是** `iio-sensor-proxy` 包的依赖，
KDE Mobile 的包集里不一定有；缺任何一个，`ssccli` 和代理都会在动态链接阶段退出。

- `install` 时按包名检查，缺的（KDE Mobile 包集和 Workstation 不一样）直接从容器仓库抓下来装进树，不再等真机；
- `tools/verify-tree-runtime.py` 再按 soname 查：读 ELF 的 `PT_INTERP` 和 `DT_NEEDED`，
  沿着依赖链（`libssc → libqmi-glib → libqrtr-glib`）逐个到树的库目录里找。
  工作流在整理树之后跑，失败就不出镜像。

## 改了什么

| 文件 | 改动 |
|---|---|
| `device/fedora-overlay/.../liuqin-hexagonrpcd-sdsp.service` | `-R` 写死为树里的布局 |
| `tools/build-liuqin-sensors-rpm.sh` | 不再卸 Fedora 的包；只装 `/usr/libexec` 下的二进制（不装激活条目）；检查发行包与三个运行库；补丁集扩到 0008–0010 |
| `device/fedora-overlay/.../iio-sensor-proxy.service.d/90-liuqin-ssc.conf` | `ExecStart=` 指向我们的二进制，补 `AF_QIPCRTR` |
| `tools/build-liuqin-fedora-rootfs.sh` | 不再软链 `sns_reg_version`，删掉四个无效软链，断言它是实体文件 |
| `device/sensors/patches/0008..0010` | 从参考项目导入，作者与说明原样保留 |
| `tools/verify-liuqin-rpms.sh` | 断言我们的包不含发行包的任何路径 |
| `tools/verify-tree-runtime.py` + 工作流两步 | 在 CI 上查运行库、代理启动链和 `-R` 路径 |

## 上机确认（一次刷机就够）

1. 重出 `liuqin-sensors` RPM、重装进树、重装镜像，刷 `boot_a` + `userdata`；
2. 首启后跑 `provision-liuqin-from-persist.sh /`，输出里应有 `registry=<三位数>`；
3. **重启**。DSP 的传感器列表是开机那一刻按 registry 建的：开机时 registry 还是空的
   （`liuqin-slpi` 会打 "registry not imported yet"），provision 之后不重启，DSP 不会
   重新读它，`ssccli` 只会得到"没有这个传感器"，代理也就起不来；
4. 依次看：

```sh
rpm -q iio-sensor-proxy
systemctl status liuqin-slpi liuqin-hexagonrpcd-sdsp liuqin-ssc-sample-gate --no-pager
cat /run/liuqin-sensors/accelerometer-ready
journalctl -u liuqin-hexagonrpcd-sdsp -b | grep -i 'sns_reg\|registry\|Could not open'
busctl --system tree net.hadess.SensorProxy | head
monitor-sensor
```

先做两项**不依赖日志**的确认（这两条能直接判定前缀对不对）：

```sh
# 设备树实际给出的名字（daemon 就是按这两个属性猜目录的）
cat /proc/device-tree/model; echo
tr '\0' '\n' < /proc/device-tree/compatible
# 单元实际用的前缀，和树里有没有这个目录
systemctl show -p ExecStart liuqin-hexagonrpcd-sdsp.service
ls /usr/share/qcom/sm8450/Xiaomi/liuqin/sensors/
```

判据：

- `ssccli --sensor=accelerometer` 报 `Unable to initialize ... UNKNOWN`：libssc 已经连上
  SSC、也看到了内置的 `registry` 传感器，但 DSP 的列表里没有加速度计——先确认是不是
  没重启（见第 3 步）；
- 单元里没有 `-R /usr/share/qcom/sm8450/Xiaomi/liuqin`，或那个目录缺 `config/` →
  前缀不对；`journalctl -u liuqin-hexagonrpcd-sdsp` 里出现的 `Could not open` /
  `Could not stat` 行会带出固件实际请求的路径（daemon 的 `apps_std.c` 会把这些打到
  stderr），拿它和树里的路径对一遍；
- gate 是 failed → 看 `/run/liuqin-sensors/ssccli-accelerometer.log`，问题在 ssccli
  与固件之间；
- 代理出现、`HasAccelerometer=true`、`monitor-sensor` 能报方向 → 这条链通了；
- 代理正常但桌面不旋转 → 是 KDE 侧读取代理的那一环（参考项目那两个 refresh 单元是
  GNOME 专用的，不能照搬），另查。
