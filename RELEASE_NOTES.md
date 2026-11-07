## 更新内容

- 时间轴两端拖动都会预览对应画面，直接封装按选区控制播放范围。
- 新增 **0.25×–4×** 播放速度；默认最终播放时长不超过 **3 秒**。
- 拖动选区两端可以自定义时长；「重置为 3 秒」恢复默认行为。
- GIF 处理前显示采样体积预估，处理后显示实际大小。
- 「关于」加入 GitHub 项目链接，并修复菜单语言切换后的显示问题。

## 下载与安装

下载 **LivePhotoStudio-1.1-universal.dmg**，退出旧版后将应用拖入「应用程序」。支持 **macOS 14+、Apple 芯片与 Intel**，运行不需要额外安装 FFmpeg、Python 或 Homebrew。当前包为 ad-hoc 签名，尚未使用 Apple Developer ID 签名与公证。

## 验证范围

- 自动测试覆盖精确剪切、首尾帧、直接封装、变速、声音、GIF 时长与体积、默认三秒、手动时长、短素材、历史存储、取消和错误恢复。
- 界面截图覆盖中文深色、英文浅色、裁切、自定义输出、水印、GIF 体积预估和处理后大小。
- 验证使用合成媒体和本地构建流程；公开材料不包含个人文件名、路径或设备信息。

## 功能截图

![1.1 中文主界面](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/editor-1.1.png)

![1.1 比例裁切与自定义输出](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/crop-custom-1.1.png)

![1.1 水印设置](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/watermark-1.1.png)

![1.1 GIF 体积预估](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/gif-estimate-1.1.png)

![1.1 GIF 实际大小](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/gif-actual-1.1.png)

![1.1 英文浅色界面](https://raw.githubusercontent.com/latter404/LivePhotoStudio/v1.1/Assets/english-light-1.1.png)

## English

Adds synchronized trim-edge previews, 0.25×–4× speed, a three-second default output, custom duration by dragging either edge, sampled GIF size estimates and actual sizes, and the GitHub project link in About.

Download **LivePhotoStudio-1.1-universal.dmg**, quit the previous version, and replace it in Applications. The package supports macOS 14+, Apple silicon, and Intel, and is ad-hoc signed and not notarized.

**Validation scope:** automated tests cover precise timing, passthrough ranges, speed, audio, GIF duration and estimates, default and custom duration, short clips, stored results, cancellation, and error recovery. Public screenshots cover the Chinese dark UI, English light UI, crop, custom output, watermarks, and GIF estimates. The public material contains no personal filenames, paths, or device details.
