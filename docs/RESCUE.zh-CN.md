# 进入 initramfs 救援 shell

stage 1 的 initramfs 自带 BusyBox、USB 网卡和 **telnet**（不是 SSH）。
它平时不会停在 shell：只有根文件系统校验失败时才会启动救援通道。

## 触发条件

`initramfs/init` 在持久根校验失败后会：

- 建立 USB NCM/ECM 网卡，平板地址 `192.168.7.2`；
- 启动 `telnetd`，端口 `2323`；
- 只要 UFS 处于 fail-closed 状态，就保留这个 shell。

停在准入拒绝时，日志里会有 `persistent root rejected: <原因>`。最常见的是
`kernel release mismatch`：boot.img 里钉的内核版本和根里的 `kernel.release`
不是同一次构建，也就是 boot.img 和 rootfs 没有一起刷。

## 生成一个只用于救援的 boot.img

准入看的是 boot.img 里钉的 `EXPECTED_RELEASE` 和根里的 `kernel.release` 是否
相等，所以做救援镜像只要故意钉一个对不上的值：

```sh
sudo env EXPECTED_RELEASE=0-rescue \
  KERNEL_OUT="$PWD/ci/liuqin-kernel-<commit>/kernel" \
  OUT_DIR="$PWD/out/rescue-boot" \
  AUDIO_TOPOLOGY="$PWD/out/Xiaomi-Pad-6-Pro-tplg.bin" \
  FIRMWARE_POOL="$PWD/device/firmware-pool" \
  WLAN_HSP2_TUPLE="$PWD/device/wlan-tuple" \
  STOCK_OVERLAY_DIR="$PWD/device/abl-analysis/dtbo" \
  STOCK_BASE_DIR="$PWD/device/abl-analysis/vendor_boot/dtbs" \
  MKBOOTIMG_DIR="$PWD/tools/local/aosp-mkbootimg" \
  sh tools/build-liuqin-fedora-boot.sh
```

产物：

```
out/rescue-boot/boot-liuqin-native.img   192 MiB
out/rescue-boot/liuqin-firstboot.cpio.gz
```

## 退出救援

救援 boot 只换 `boot_a`。处理完后刷回 CI 的正常 boot.img：

```sh
fastboot flash boot_a boot.img
fastboot reboot
```

## 注意

- 救援镜像故意让根校验失败；它不能用来正常启动系统。
- 如果 UFS 没能进入 fail-closed，init 会拒绝启动 telnet，只在本地控制台
  显示原因；这时不要强刷。
- 不要把救援镜像留在 `boot_a` 当日常启动镜像。
