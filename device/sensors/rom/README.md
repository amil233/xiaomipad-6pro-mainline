# 平板 V14 的传感器配置

从 `V14.0.9.0.TMYCNXM` 的 `vendor_a` 分区 `/etc/sensors` 取出，共 59 个文件。
`tools/build-liuqin-sensors-stack.sh` 直接读这里，不再要求先在 `tools/local`
解包 `super.img`。

内容是这台平板 ROM 的传感器注册表和 `sns_reg_config`；换 ROM 时整目录替换，
不要和别的机型混用。
