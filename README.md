# 表盘工坊 / MiFace Studio

一个把「制作表盘」和「安装表盘」放进同一部 iPhone 的应用。

- **制作**：内置小米官方 Web 表盘编辑器（离线打包），保留图层、文字、数据绑定、亮屏/息屏、样式、导出等能力。
- **安装**：原生 CoreBluetooth 实现小米穿戴的 L2/SAR 链路、AuthKey 认证、MASS 文件传输和表盘安装，不经过电脑、不经过小米云。
- **表盘库**：管理本地工程和导出的 `.face` / `.bin` / `.mwz`，点按即可安装。

> 这是一个个人使用/侧载项目，不是上架 App Store 的成品。使用前请阅读 [NOTICE.md](NOTICE.md)。

---

## 目录

```
MiFaceStudio/
├─ App/                         # Xcode 工程（Codemagic 在这里构建）
│  ├─ project.yml               # XcodeGen 工程描述
│  ├─ ExportOptions.plist
│  ├─ WebEditor/                # 打包的小米表盘编辑器 Web 资源
│  └─ MiFaceStudio/
│     ├─ App/                   # SwiftUI 入口
│     ├─ Core/                  # 路径、模型、AppModel
│     ├─ Editor/                # WKWebView、本机 HTTP 服务、LVGL 编码、Electron shim
│     ├─ Library/               # 工程/表盘库、.face/.bin/.mwz 解析与改 ID
│     ├─ Device/                # CoreBluetooth、SAR、认证、Protobuf、MASS 安装
│     ├─ Settings/
│     ├─ UI/
│     └─ Resources/
│        └─ Assets.xcassets
├─ Research/                    # 逆向/协议资料、原型、测试样本（不参与构建）
└─ codemagic.yaml               # Codemagic 工作流（仓库根目录）
```

## 在 Codemagic 上构建

1. 把 **整个 `MiFaceStudio` 文件夹**推到 GitHub/GitLab（`codemagic.yaml` 必须在仓库根目录）。
2. 在 Codemagic 里添加这个 App，连接你的 Apple Developer 账号，创建证书和描述文件。
3. 在 Codemagic 的环境变量里确认：
   - `APPLE_TEAM_ID`：你的 10 位 Team ID（Codemagic 签名配置通常会自动注入）。
   - Bundle ID 改为你自己的，例如 `com.yourname.miface`（同时改 `App/project.yml` 和 `codemagic.yaml` 里的 `BUNDLE_ID`）。
4. 直接运行 `ios-testflight` 工作流。它会：
   - `brew install xcodegen`
   - 在 `App/` 里生成 `MiFaceStudio.xcodeproj`
   - 解析 ZIPFoundation
   - archive + export IPA
5. 构建产物在 `$CM_BUILD_DIR/ipa/`，可以下载安装或上传 TestFlight。

### 本机 Xcode

需要 macOS + Xcode 15+：

```bash
brew install xcodegen
cd App
xcodegen generate
open MiFaceStudio.xcodeproj
```

签名后选择真机运行。**必须用真机**，模拟器没有 CoreBluetooth。

## 使用流程

1. 打开「制作」，点「新建」。
2. 选表盘类型和设备（例如小米手环 9 Pro / 小米手表 S4），进入编辑器。
3. 添加背景、时间、日期、数据项，调整样式。
4. 点「导出」，按向导生成预览图和表盘文件。
5. 导出的文件会出现在「表盘库 → 表盘文件」。
6. 打开「设备」，搜索并连接手表/手环；第一次需要填 **AuthKey**。
7. 连接并认证成功后，点「安装到已连接设备」。

## AuthKey

AuthKey 是小米运动健康绑定设备时生成的 32 位十六进制密钥，用来完成蓝牙认证。

- 本 App 不会向任何服务器上传 AuthKey，只存在 iOS Keychain。
- 可以在电脑版 AstroBox 连接一次设备后，从设备详情/日志中复制 `authkey`。
- 也可以在「设备」页粘贴已有的 32 位密钥，点「保存」再点「重新认证」。

没有 AuthKey 时设备仍能被扫描/连接，但无法完成认证，也不能安装表盘。

## 当前已知限制

- **视频表盘**：编辑器调用 `ffmpeg` 的部分没有移植，暂不支持视频表盘。
- **EZIP / 专业版字体裁剪**：未实现，遇到时会提示改用普通压缩/静态字体。
- **I8 索引色**：编码器会回退为 ARGB8888（文件更大但可显示）。普通表盘通常走 true-color 路径。
- **必须在前台安装**：iOS 不允许普通 App 在后台维持长时间 BLE 传输；安装时请保持屏幕亮起、App 在前台。
- **不同固件差异**：第三方安装能力取决于设备/固件；部分型号可能拒绝未签名表盘。安装失败不会影响官方表盘。
- **编辑器资源版权**：`Resources/WebEditor` 来自小米官方 Web 版，仅用于个人互操作/学习；不要把它用于商业分发或上架。详见 `NOTICE.md`。
- **App Store**：本项目包含 AGPL 协议实现和第三方编辑器资源，**不建议直接上架 App Store**；建议自签、Ad Hoc 或内部 TestFlight。

## 技术要点

- 编辑器是官方 Web 应用；通过 `EditorShim.js` 提供 Electron 的 `window.electron`（fs/path/ipc），把文件读写转到本机 `127.0.0.1` 临时 HTTP 服务。
- `LocalWebServer` 只监听 loopback，每次启动生成随机 token。
- `LVGLImageEncoder` 复刻 LVGLImage 的 `.bin` 容器和 RLE 编码（12 字节头、LVGL v9 格式）。
- 蓝牙协议：L1 帧（A5A5 / CRC16-ARC）、SAR 窗口与 ACK、L2 通道、AES-CTR（key 即 IV）、AES-CCM（4 字节 tag）、miwear-auth KDF、MASS 分片、WatchFace Prepare/Install。
- 表盘 ID：`.face`/`.bin` 在偏移 34 的 24 字节字段内找 9/12 位 ID；`.mwz` 同时改 `description.xml`、`manifest.xml` 和内部 `.bin`。

## 参考与署名

协议实现参考了 [AstroBox-NG](https://github.com/AstralSightStudios/AstroBox-NG) 的公开模块（AGPL-3.0，附加署名条款）。表盘编辑器界面与资源版权归小米。完整说明见 [NOTICE.md](NOTICE.md)。
