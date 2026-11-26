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

用当前的 `native-root.hashes` 和对应的内核产物，故意改坏一个被清单钉住的
文件哈希：

```sh
sh tools/build-liuqin-rescue-boot.sh \
  --hashes native-root.hashes \
  --kernel ci/liuqin-kernel-<commit> \
  --out out/rescue-boot
```

产物：

```
out/rescue-boot/boot-liuqin-native.img   192 MiB
out/rescue-boot/liuqin-firstboot.cpio.gz
```

它只改 ramdisk 里的文件清单，不动 rootfs、不动 GPT。刷入：

```sh
fastboot flash boot_a out/rescue-boot/boot-liuqin-native.img
fastboot reboot
```

## 从主机连接

平板启动后，主机会多一个 USB 网卡。可以等 DHCP，或手动配地址：

```sh
sudo ip address add 192.168.7.1/24 dev <usb网卡>
telnet 192.168.7.2 2323
```

进入的是 BusyBox 的 root shell，没有登录认证，只应直连自己的电脑。

## shell 里有什么

`busybox --list` 里可用：

```
fdisk dd mke2fs mount umount nc wget tar telnet
```

**没有 `sgdisk`**。所以：

- 只是查看分区：`fdisk -l /dev/sda`；
- 要写块设备：先确认 `blockdev --getro /dev/sda`，必要时
  `blockdev --setrw /dev/sda`；
- 完整恢复原厂 GPT 不建议在这个 shell 里手工做；用 fastboot 的
  `flash partition`、EDL/QFIL，或者回到正常的系统里用 `sgdisk`。
- 如果只是要把 `linux_home` 改名成 `userdata`，在正常的系统里做更安全：

  ```sh
  sudo sgdisk --change-name=37:userdata /dev/sda
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
