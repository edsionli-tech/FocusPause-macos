# FocusPause 标准 macOS App 工程

这个目录是整理后的标准 macOS App 工程目录：

- `FocusPause.xcodeproj`：标准 Xcode 工程。
- `FocusPause/`：App 源码、资源和配置。
- `FocusPause/Info.plist`：应用元信息、菜单栏 App 标识、提醒事项权限说明。
- `FocusPause/FocusPause.entitlements`：App Sandbox 与导出文件所需权限。
- `FocusPause/Assets.xcassets/AppIcon.appiconset`：标准 macOS App 图标位。

## 在 Xcode 中运行

1. 打开当前目录下的 `FocusPause.xcodeproj`。
2. 选择 `FocusPause` scheme。
3. 在 target 的 `Signing & Capabilities` 中选择你的 Team。
4. 点击 Run。

## 配置 App 图标

在 Xcode 左侧打开 `FocusPause/Assets.xcassets/AppIcon`，按 macOS AppIcon 的尺寸位拖入图标：

- 16x16、32x32、128x128、256x256、512x512
- 每个尺寸都需要 `1x` 和 `2x`

## 构建验证

可以在当前目录运行：

```sh
xcodebuild -project FocusPause.xcodeproj -scheme FocusPause -configuration Debug -destination 'platform=macOS' -derivedDataPath build/XcodeDerivedData CODE_SIGNING_ALLOWED=NO build
```
