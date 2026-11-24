# 验证 g_idle 冷启动顺序（待做）

目的：确认把 `find_sensors` 从 `name_acquired_handler` 移到 `g_idle_add`
之后，早到的 Claim 仍能正确启动传感器，正常启动和 GNOME 客户端不回归。

当前代码没有采用这个生产改动；CI 用的是测试闸门（补丁 `0007`）。本测试通过
后再决定是否替换闸门。测试只需要替换 `liuqin-sensors` 包，不需要重装系统。

## 准备

- 平板当前能正常进入 Ubuntu 桌面；
- 准备一个带 `g_idle_add` 改动的 `liuqin-sensors_0.1_arm64.deb`；
- 备份旧包和旧二进制：

```sh
dpkg -S /usr/local/libexec/liuqin-iio-sensor-proxy
sudo cp -a /usr/local/libexec/liuqin-iio-sensor-proxy /root/liuqin-iio-sensor-proxy.old
sudo apt install dpkg-repack
dpkg-repack liuqin-sensors
```

把旧 deb 放到 `/root/`，后面回滚用。

## 1. 安装测试包并打开日志

```sh
sudo apt install /tmp/liuqin-sensors_0.1_arm64.deb
sudo mkdir -p /etc/systemd/system/iio-sensor-proxy.service.d
printf '[Service]\nEnvironment=G_MESSAGES_DEBUG=all\n' |
  sudo tee /etc/systemd/system/iio-sensor-proxy.service.d/debug.conf
sudo systemctl daemon-reload
```

## 2. 早到 Claim

把 [`tests/device-early-claim.py`](../tests/device-early-claim.py) 拷到平板：

```sh
scp tests/device-early-claim.py liuqin:/tmp/
```

在平板上执行：

```sh
sudo systemctl stop iio-sensor-proxy
sudo python3 /tmp/device-early-claim.py > /root/early-claim.log 2>&1 &
sleep 0.5
sudo systemctl start iio-sensor-proxy
wait
cat /root/early-claim.log
sudo journalctl -b -u iio-sensor-proxy --no-pager | tail -80
```

期望：

- `HasAccelerometer after claim` 是 `false`；
- 日志顺序是 `ClaimAccelerometer` 早于 `Found device`；
- `Enabling sensor (` 只出现一次；
- 随后 `HasAccelerometer` 变 `true`，`AccelerometerOrientation` 变为 `left-up`。

如果 claim 时已经是 `true`，说明发现仍抢在 claim 前面，改动没有达到目的。

## 3. 正常启动

不运行 early-claim，直接重启：

```sh
sudo reboot
```

启动后检查：

```sh
systemctl status iio-sensor-proxy
monitor-sensor
journalctl -b -u iio-sensor-proxy --no-pager
```

确认：

- 服务 active，没有重启循环；
- `monitor-sensor` 能看到加速度计，旋转平板时方向变化；
- 属性在启动后正常发布，没有客户端超时；
- 日志没有 critical 或重复启动。

## 4. 回归

```sh
# 两轮 claim / release
gdbus call --system --dest net.hadess.SensorProxy \
  --object-path /net/hadess/SensorProxy \
  --method net.hadess.SensorProxy.ClaimAccelerometer
gdbus call --system --dest net.hadess.SensorProxy \
  --object-path /net/hadess/SensorProxy \
  --method net.hadess.SensorProxy.ReleaseAccelerometer

sudo systemctl restart iio-sensor-proxy
sudo systemctl suspend
```

唤醒后再次运行 `monitor-sensor`，确认方向正常、没有卡住的 claim、
`Enabling sensor (` 没有重复累积。

## 5. 判定

全部满足才算通过：

- 早到 claim 时 `HasAccelerometer` 为 `false`，claim 成功，随后方向正常；
- claim 早于 `Found device`，`Enabling sensor (` 只有一次；
- 正常启动、GNOME、`monitor-sensor`、suspend/resume、claim/release 都不回归；
- 没有 D-Bus 超时、服务重启循环、critical 日志。

通过后再把 `g_idle_add` 改动合入，并移除测试闸门；不通过则保留闸门，只改测试。

## 6. 回滚

```sh
sudo apt install /root/liuqin-sensors_0.1_arm64.deb
sudo rm -f /etc/systemd/system/iio-sensor-proxy.service.d/debug.conf
sudo systemctl daemon-reload
sudo reboot
```

## 记录

测试时记下：

- 平板当前内核版本（`uname -r`）；
- 测试包来源和构建时间；
- early-claim 日志的关键行；
- 正常启动后 `HasAccelerometer` 变为 `true` 的大致时间；
- 是否通过，以及失败时的日志。
