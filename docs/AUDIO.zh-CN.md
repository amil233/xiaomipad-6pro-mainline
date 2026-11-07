# 音频（扬声器 TDM）状态与驱动改动

**状态（2026-11-07）**：外放已出声，`speaker-test -c 4` 与 GNOME 桌面播放
都已验证。底层测试命令：

```sh
speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1
```

四颗 CS35L41 挂在同一条 TDM 总线上，DSP 侧按 48 kHz / 4 声道 / 24-bit /
4×32-bit slot 的厂商线格式输出。内核基线 `liuqin-7.3`，相关提交：

| 提交 | 主题 |
|---|---|
| `c8778035ea23` | `ASoC: qcom: sc8280xp: leave TDM backend params to the stream` |
| `79ed40f4ed38` | `ASoC: cs35l41: program the ASP RX slot from the TDM mask` |
| `ce85b3f7efc2` | `ASoC: qcom: sc8280xp: frame TDM codecs with DSP_A and one slot per amp` |
| `52866ba809f1` | `ASoC: qcom: sc8280xp: program the codec PLL reference on TDM links` |

## 1. 数据通路

```
ALSA FE (q6apm-dai, PCM 2..8ch)
  → AudioReach 图：MODULE_ID_PCM_CNV + MODULE_ID_TDM_SINK
       （厂商拓扑 qcom/sm8450/Xiaomi-Pad-6-Pro-tplg.bin）
  → LPASS TERTIARY_TDM_RX_0（4 slot × 32 bit，active mask 0xf）
  → I2C 上的四颗 CS35L41（TL/TR/BR/BL），每颗用 ASPRX1 取一个 slot
```

- DTS 里的 speaker 链路：[`sm8475-xiaomi-liuqin.dts`](../arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dts)
  的 `speaker-playback-dai-link`，`dai-tdm-slot-num = <4>`、`-width = <32>`、
  `-rx-mask = <1 1 1 1>`。
- 厂商线格式来自 `backend_conf.xml` / cape resource manager：48 kHz、4 声道、
  24-bit、slot 0..3。`S24_LE` 的物理容器是 32 bit，q6apm 只接受 16/32-bit
  串行 slot，所以是 4×32。

## 2. 四个内核改动

### 2.1 TDM 后端参数不再被 BE fixup 覆盖（`c8778035ea23`）

**现象**：`speaker-test` 的 prepare 报 `-EINVAL`，dmesg 里
`Failed to set media format -22`（来自 `q6apm-lpass-dais`，不是 DSP 拒绝）。

**根因**：`sc8280xp_be_hw_params_fixup()`（`sound/soc/qcom/sc8280xp.c:283`
附近）把所有后端钉成 48 kHz / `S16_LE` / 2 声道——这是 WCD938x、DP0 这些
codec-DMA 后端的约定。DPCM 会把 fixup 后的参数原样交给 TDM 后端，于是
`audioreach_tdm_set_media_format()`（`sound/soc/qcom/qdsp6/audioreach.c:1120`）
的守卫（要求 48k/24bit/4ch/mask 0xf/4 slot/32-bit）直接返回 `-EINVAL`，
报文根本没发给 DSP。

**改动**：TDM 端口范围（`PRIMARY_TDM_RX_0 ... QUINARY_TDM_TX_7`）直接跳过
fixup，让协商出来的流格式原样到达 DSP TDM 端口和功放。

**上游对照**：v7.4-rc1 的同一函数仍然无条件强制这三个值，上游的 TDM 用户
跑的是 2ch/S16 的 Audio IF 拓扑；本板是 4ch/24-bit 的 TDM_SINK 拓扑，所以
这是**必须保留的下游偏离**。

### 2.2 cs35l41 支持 TDM slot 选择（`79ed40f4ed38`）

同一 TDM 总线上的每颗功放只解一个 slot，但主线 cs35l41 只有
`.set_channel_map`，没有任何 TDM 机器驱动会调用它。

新增 `.set_tdm_slot`（`sound/soc/codecs/cs35l41.c:739`）：把 rx mask 的
置位按顺序翻译成 ASPRX1/ASPRX2 的 slot 号，经 `cs35l41_set_channels()`
写入 `CS35L41_SP_FRAME_RX_SLOT`；空 mask 恢复硬件默认（slot 0/1），
普通立体声 I2S 链路行为不变。写法照上游 cs35l36 的
`f390794e6354`。

### 2.3 TDM 链路用 DSP_A，每颗功放一个 slot（`ce85b3f7efc2`）

**根因**：机器驱动把卡级的 `codec_dai_fmt`（sm8450 上是 I2S，给 MI2S/HDMI
链路用）也套在了 TDM 后端的 codec 上；codec 的 slot 又来自共享的 codec
节点（没有 mask）。结果四颗功放都把前两个 slot 当成立体声 I2S 来解，
slot 2/3 从未被消费。

**改动**（`sound/soc/qcom/sc8280xp.c:143`、`:162`）：

- TDM 分支对每颗 codec 强制 `SND_SOC_DAIFMT_CBC_CFC | NB_NF | DSP_A`，
  让功放在帧同步脉冲上锁存、再数后续 slot；
- 按链路里 codec 的顺序，第 N 颗下发 `BIT(N)`（TL/TR/BR/BL → slot 0..3）。

**上游对照**：sdm845 的 `ed41c80271e6`（TDM codec 用 DSP_A）与
`84c3a8e05ce8`（每颗扬声器各自的 RX mask）是同一模式。

### 2.4 TDM 链路的 codec PLL 参考（`52866ba809f1`）

**现象**：上面三项都生效后仍然完全无声，且没有任何错误——hw_params、
prepare、start 全部成功，dmesg 干净。

**根因（7.3 合并丢失）**：6.17 的 `sc8280xp_tdm_hw_params()` 有一段
liuqin 专用逻辑，对每颗功放调用
`snd_soc_component_set_sysclk(component, CS35L41_CLKID_SCLK, 0, bclk_freq, ...)`，
即用 6.144 MHz 的 TDM bit clock 作 PLL 参考并打开 PLL。v7.3 合并时这段被
通用的 `codec_sysclk_set` 块取代：该标志在 `sm8450_priv_data` 里是 false，
而且通用块只调 `snd_soc_dai_set_sysclk()`——cs35l41 的 **DAI 回调只写 FS
monitor（`TST_FS_MON0`），真正编程 `PLL_CLK_CTRL` 的只有 component 回调**。
PLL 不使能 ⇒ 功放内部 DSP/保护链没有时钟 ⇒ 输出一直静音，而所有 ASoC
调用仍然返回成功。

**改动**（`sound/soc/qcom/sc8280xp.c:181`）：TDM 分支对每颗 codec 同时调用
DAI 和 component 两个 sysclk（cs35l41 里 clk_id 0 就是 `CLKID_SCLK`），
`-ENOTSUPP` 容忍。模式与上游 v7.4 给 sdm845 的修复 `5e9f324509a7` 一致。

**验证**：`PLL_CLK_CTRL`（0x2C04）应读到 `0x00000510`
（bit4 = PLL enable，bits10:5 = 0x28 = 6.144 MHz）。

## 3. 诊断要点（避免再踩）

1. **`snd_soc_dai_set_tdm_slot()` 会把 0 mask 展开成 `(1 << slots) - 1`**
   （`sound/soc/soc-dai.c:348` 的 `snd_soc_xlate_tdm_slot_mask()`）。所以
   dmesg 里 `TDM mask 0xf names more slots than the codec receive channels`
   是通用 `qcom_snd_apply_dai_tdm_slots_cfg()` 用 codec 节点的空 mask 触发
   的，良性；逐颗 amp 的真实 mask 由后面的循环再写。
2. **TDM 守卫是本地实现**：厂商拓扑用的是 `MODULE_ID_TDM_SINK`，不是上游
   的 Audio IF 路径；守卫拒绝参数时不会产生 `DSP returned error[...]`，
   只有 `Failed to set media format -22`。
3. **合并盲区**：板级特殊分支会被上游重构静默吞掉（本次是 PLL 调用；
   同类先例是 7.3 丢过 ubwc 的 `qcom,cape` 机器别名）。升级后按关键字
   grep：`CS35L41_CLKID`、`codec_sysclk_set`、`TERTIARY_TDM`、
   `audioreach_tdm_set_media_format`。
4. **播放前清 dmesg** 再抓日志，避免混入 PipeWire 的重试。

## 4. 已知限制与待办

- **守卫只接受一种 PCM 元组**：48 kHz / 4 声道 / `S24_LE`。实测 GNOME 桌面
  （PipeWire）能协商出该守卫接受的元组并正常出声；但若有应用强制 2ch 或
  `S16_LE`，prepare 仍会返回 `-EINVAL`（数据通路本身没问题）。届时二选一：
  1. 用户态把该 sink 固定成 4 声道（WirePlumber/ALSA profile）；
  2. 内核/DSP 侧做 2→4 上混（PCM 模块的 channel map 或 TDM sink 的映射）。
- **槽位与物理喇叭的对应**：当前按链路顺序 TL/TR/BR/BL → slot 0/1/2/3。
  若实际听感左右/上下颠倒，改 `sc8280xp.c` 里下发 `BIT(i)` 的对应表即可。
- **耳机/麦克风**走 WCD938x（SoundWire），与扬声器 TDM 链路互相独立；
  耳机的验证与上面四项改动无关。
- `cs35l41` 的喇叭保护 DSP 固件（`cs_dsp`）与标定链是厂商移植部分，
  本次没有改动；如果以后出现“有声音但音量/保护异常”，从那里查。
