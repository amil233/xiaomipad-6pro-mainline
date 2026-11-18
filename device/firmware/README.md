# device/firmware —— liuqin 板级固件集

`usr/lib/firmware/` 下跟踪的固件覆盖本机所需：SM8475 DSP（adsp/cdsp/slpi）、
QCA6490 WLAN（ath11k WCN6855，含项目生成的 `board-2.bin`）、QCA6490 蓝牙、
Novatek NT36532 触摸固件（两种面板）、Adreno 730 GPU、CS35L41/CS35L63
音频 DSP、音频拓扑（`qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin`）、VPU blob
与无线 regulatory 数据库。逐文件 sha256 钉在 `firmware.manifest`。

## 来源（当前状态，务必读）

- **唯一受支持的 ROM 输入是本机 `V14.0.9.0.TMYCNXM`。** 不要使用
  `OS2.0.6.0`（那是参考项目 yzddmr6 的 ROM），也不要把其他机器的
  `persist`/校准数据放进这里。
- **当前树内的 blob 仍是 2026-10-20 从 `OS2.0.6.0` 导入的旧集**
  （提交 `dea2482`）。与本地 V14 提取池 `tools/local/firmware-liuqin/`
  对比：201 个跟踪文件中 135 个哈希不同、36 个在池里没有同名件。
  触摸固件即为例：树内 `novatek_nt36532_m81_fw_tm.bin` 是 `3d9737da…`，
  V14 池里是 `267f5eb0…`。
- 因此**在重新提取 V14 之前，不能声称这套固件来自 V14**。重提取步骤见
  `../docs/STATUS.zh-CN.md` §7：解包 V14 `super.img` → 重摆 pool →
  运行 `tools/build-liuqin-firmware-prep.sh` → 替换本目录并重写 manifest →
  冷启动验证 Wi-Fi/蓝牙/触控/音频/GPU。
- 生成工具：`tools/build-liuqin-firmware-prep.sh`；每台机器独有的
  扬声器保护校准、传感器 registry、WLAN MAC、蓝牙地址**永远不放在这里**，
  安装/运行时从本机 persist 读取（`tools/provision-liuqin-from-persist.sh`）。

## 许可 / 声明

这些二进制属于 Qualcomm Technologies、Xiaomi、Cirrus Logic 及其许可方。
跟踪它们只是为了让 Xiaomi Pad 6 Pro 的所有者能构建并运行自己已拥有的系统，
不授予此外的任何权利。详见仓库根 `NOTICE`。权利方如有异议，请开 issue，
文件会被移除。
