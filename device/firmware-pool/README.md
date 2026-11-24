# 固件池

从 `V14.0.9.0.TMYCNXM` 提取的原始固件：蓝牙、触摸、GPU、DSP、WLAN，以及
`vpu20_4v.mbn`。`tools/build-liuqin-firmware-prep.sh` 用它和跟踪的
`device/wlan-tuple`、AudioReach 拓扑一起生成 `device/firmware`。

不要在这里放每机校准（MAC、蓝牙地址、喇叭校准、传感器 registry）。
