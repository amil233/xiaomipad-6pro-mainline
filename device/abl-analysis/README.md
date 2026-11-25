# ABL overlay 与基设备树

从 `V14.0.9.0.TMYCNXM` 的 `dtbo.img` 和 `vendor_boot.img` 解出的 ABL overlay
入口（`dtbo/`）和基 DTB（`vendor_boot/dtbs/`），只用于装配 boot.img。

这些是启动镜像的输入，不进 rootfs；换 ROM 时整体替换并用
`tools/extract-v14-vendor.sh` 重新生成。
