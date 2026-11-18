# device/firmware —— liuqin 板级固件集（V14.0.9.0.TMYCNXM）

`usr/lib/firmware/` 下跟踪的 **173 个文件 + 4 个符号链接**覆盖本机所需：
SM8475 DSP（adsp/cdsp/slpi，68 件）、QCA6490 蓝牙（89 件）、QCA6490 WLAN
（ath11k WCN6855，含项目生成的 `board-2.bin`）、Novatek NT36532 触摸固件
（两种面板）、Adreno 730 GPU、CS41 音频 DSP、AudioReach 拓扑
（`qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin`）、VPU blob。逐文件 sha256 钉在
`firmware.manifest`。

## 来源（2026-11-18 已按 V14 重提取）

唯一 ROM 输入是本机 **`V14.0.9.0.TMYCNXM`**（Android 13 线刷包）：

| 内容 | 提取方式 |
|---|---|
| 触摸、GPU、VPU、WLAN 板号 | `super.img` → `simg2img` → `lpunpack.py -p vendor_a` → `vendor_a.img` 是 EROFS，用 `fsck.erofs --extract` 取 `/firmware` |
| DSP 68 件 | `NON-HLOS.bin`（FAT）→ `mcopy` 取 `image/` |
| 蓝牙 89 件 | `BTFM.bin`（FAT）→ `mcopy` 取 `image/` |
| 音频拓扑 | 仓库 `tools/build-liuqin-audio-topology.sh` 构建 |
| WLAN 运行时 | `out/wlan` 的 V14 HSP2 tuple + 上游 WCN6855 |

生成器：`tools/build-liuqin-firmware-prep.sh`。关键值：触摸
`709726ba…`（CSOT）/`267f5eb0…`（TM）、VPU `cc27f8e3…`、A730 SQE
`8df3e5ab…`；蓝牙池与 V14 `BTFM.bin` 的 89 个文件逐一相同。

旧 OS2 集少掉的 22 个蓝牙 patch 变体、`regulatory.db` 是有意删除：V14 没有
这些文件，regdb 由内核内建。**不要**再从 `OS2.0.6.0`（参考项目 yzddmr6 的
ROM）拷固件回来。

## 每台机器独有的数据

扬声器保护校准（`cirrus/*-calr.bin`）、传感器 registry、WLAN MAC、蓝牙地址
**永远不放在这里**；安装/运行时从本机 persist 读取
（`tools/provision-liuqin-from-persist.sh`）。

## 许可 / 声明

这些二进制属于 Qualcomm Technologies、Xiaomi、Cirrus Logic 及其许可方。
跟踪它们只是为了让 Xiaomi Pad 6 Pro 的所有者能构建并运行自己已拥有的系统，
不授予此外的任何权利。详见仓库根 `NOTICE`。权利方如有异议，请开 issue，
文件会被移除。
