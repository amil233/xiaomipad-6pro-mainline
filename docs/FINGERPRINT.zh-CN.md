# 指纹（可选，默认不装）

通用 rootfs **默认不包含** `liuqin-fingerprint`。原因是参考项目的 v0.6.0
预编译包绑定 6.17 内核和 26.04 的 libfprint `0ubuntu1`，与现在的 7.3 +
26.04.1 不匹配；指纹本身也还没有在这台平板上重新验收。

需要指纹时，用当前仓库源码和当前内核模块自己构建。

## 前提

- 当前内核 artifact 的 `kernel-modules/modules.tar` 里有
  `fpc1264_spi_diag.ko`；
- 平板 `modem_a` 里的 `fpcliu.mdt`、`fpcliu.b*`；
- 26.04.1 构建环境，装有 `libfprint-2-tod-dev`、`libfprint-2-dev`、
  `meson`、`ninja`、`pkg-config`、`gcc` 和 fprintd 构建依赖；
- 解压好的 fprintd 1.94.5 源码，路径放在 `FPRINTD_SOURCE`；
- 一份填好的候选配置（`device/fingerprint/oem/candidate-config.example.json`
  为基础）。

候选配置至少要写：

```json
{
  "linux_username": "你的用户名",
  "linux_uid": 1000,
  "kernel_release": "当前 7.3 内核的 uname -r",
  "base_kernel": "当前内核 commit",
  "boot_image_sha256": "当前 boot.img 的 sha256",
  "enrollment_interface": "fprintd",
  "deployment_mode": "installed"
}
```

## 构建

```sh
# 1. 从当前内核 artifact 取模块
mkdir -p out/fpc-module
tar -xf ci/liuqin-kernel-<commit>/kernel-modules/modules.tar -C out/fpc-module
module=$(find out/fpc-module -name fpc1264_spi_diag.ko | head -1)

# 2. 从平板 modem_a 取 OEM 固件（只在本机使用）
sudo mkdir -p /mnt/modem_a
sudo mount -o ro /dev/disk/by-partlabel/modem_a /mnt/modem_a
mkdir -p out/fingerprint-firmware
sudo cp /mnt/modem_a/image/fpcliu.* out/fingerprint-firmware/
sudo chown -R "$USER" out/fingerprint-firmware
sudo umount /mnt/modem_a

# 3. 构建并打包
FPRINTD_SOURCE=/path/to/fprintd-1.94.5 \
sh tools/build-liuqin-fingerprint-self.sh \
  --kernel-module "$module" \
  --firmware out/fingerprint-firmware \
  --candidate-config /path/to/candidate.json \
  --revision 7.3-1 \
  --out out/fingerprint-self
```

产物：

```
out/fingerprint-self/fingerprint-build-inputs.tar.gz
out/fingerprint-self/debs/liuqin-fingerprint_7.3-1_arm64.deb
```

## 装回镜像

把自建的输入包显式传给 rootfs：

```sh
FINGERPRINT_BUNDLE=$PWD/out/fingerprint-self/fingerprint-build-inputs.tar.gz \
  sudo sh tools/build-liuqin-rootfs.sh --rootfs-only --fingerprint
```

CI 默认不跑指纹；需要时把同样的 `FINGERPRINT_BUNDLE` 和 `--fingerprint`
加进 workflow。

## 真机验收

安装 deb 后重启，依次确认：

1. Settings → Users → Fingerprint Login 能录入；
2. GDM 登录和锁屏能用同一手指解锁；
3. 另一只手指被拒绝；
4. 普通重启后仍然可用，不需要手工预热 TEE；
5. 密码登录始终保留。

失败或不确定时回滚到不带指纹的包：

```sh
sudo apt remove liuqin-fingerprint liuqin-device
```

## 边界

- 预编译 v0.6.0 包只用于历史参考，不再作为默认输入；
- 指纹涉及 TEE/RPMB 和真实凭据写入，CI 只能证明“编译和打包”，不能替代真机验收；
- 通过前不要把指纹加回通用镜像。
