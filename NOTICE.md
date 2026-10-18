# NOTICE / 署名与第三方声明

本项目是个人使用的互操作工具，目标是让用户在自己拥有的设备上制作和安装表盘。项目不隶属于小米，也不代表小米官方。

## 1. Xiaomi Watchface Editor

`App/WebEditor/` 中的 HTML、JavaScript、CSS、图标和字体引用来自小米官方面向桌面工具分发的 Web 表盘编辑器：

- `https://cdn.cnbj1.fds.api.mi-img.com/watchface-renderer-normal/`（构建时间 2026-09-29）
- 相关辅助资源：`https://cdn.cnbj1.fds.api.mi-img.com/watchface-editor-release/`

这些资源的版权归 **小米科技有限责任公司 / Xiaomi Inc.** 所有。本项目仅将其打包用于个人设备上的表盘制作与互操作研究，**不用于商业分发，也不作为 App Store 商品**。如果你要公开发布本项目，请自行替换为自研编辑器，或取得小米授权。

## 2. AstroBox-NG

蓝牙协议栈（L1/SAR/L2、认证流程、MASS 传输、表盘安装顺序）参考并移植自：

- **AstroBox-NG** — https://github.com/AstralSightStudios/AstroBox-NG
- 公开模块：`AstroBox-NG-Module-Core`、`AstroBox-NG-Module-Bluetooth`、`AstroBox-NG-Module-Pb`
- 作者：AstralSightStudios 及其贡献者
- 许可：**AGPL-3.0**，并包含额外署名条款（以中文版为准）

按 AGPL-3.0 及附加条款，任何分发本项目的行为都必须保留上述仓库地址、作者署名，并以 AGPL-3.0 开源对应源代码。**因此本项目不应直接上架 App Store。** 个人自签、Ad Hoc 或内部 TestFlight 使用不受影响。

## 3. ZIPFoundation

`App/project.yml` 通过 Swift Package Manager 引入：

- **ZIPFoundation** — https://github.com/weichsel/ZIPFoundation
- 许可：MIT

## 4. 其他

- LVGL 图像容器格式参考 LVGL v9 的 `lv_image_header_t` / `LVGLImage.py`（MIT）。
- 小米、手环、手表等名称是小米的商标，仅用于说明兼容设备。
- 本项目不包含小米的私钥、账号凭据或云端服务；AuthKey 由用户自行提供并仅保存在本机 Keychain。

## 5. 使用风险

第三方表盘安装可能因设备型号、固件版本、地区版本而失败。请先备份官方表盘，不要在重要场合依赖本工具。作者不对设备变砖、数据丢失或账号风险承担责任。
