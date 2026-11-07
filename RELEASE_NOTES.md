## 项目介绍

实况工坊是一个原生 macOS 视频处理工具，用于将视频片段制作成实况照片或 GIF。项目以本机处理为主，不依赖外部运行时服务。

## 已实现功能

- 视频拖放导入、时间轴选段和封面选择
- 实况照片和 GIF 输出
- 常见比例裁切、自由裁切、左右 90° 旋转和水印
- 原始尺寸优先，以及可选的输出分辨率和帧率
- 添加到照片、隔空投送、JPG + MOV 文件导出
- Finder 一级右键入口、简体中文／English、浅色／深色外观和首次使用引导

## 下载与安装

下载 **LivePhotoStudio-1.0-universal.dmg**，打开后将「实况工坊.app」拖入「应用程序」。源码包为 **LivePhotoStudio-1.0-source.zip**，校验值见 **SHA256SUMS.txt**。

支持 **macOS 14+、Apple 芯片与 Intel**。当前包为 ad-hoc 签名，尚未使用 Apple Developer ID 签名与公证；首次打开可能出现 macOS 来源验证提示。

## 验证范围

- 自动测试覆盖 Live Photo 配对、时间范围、裁切、旋转、水印、输出文件和失败清理。
- 构建流程检查通用包、Finder 扩展、资源和签名状态。
- 本版使用合成媒体和本地构建流程验证，不把特定设备或私人文件作为公开兼容性承诺。

MIT 许可及 Revive、makelive 的第三方许可文件随源码和应用提供。

## English

LivePhoto Studio is a native macOS tool for turning video clips into Live Photos or GIFs with local-first processing.

**Implemented:** drag-and-drop import, timeline trimming, cover selection, Live Photo and GIF output, crop, 90° rotation, watermarks, original-size preference, custom output settings, Photos, AirDrop, paired JPG + MOV export, Finder entry, Simplified Chinese/English, light/dark appearance, and first-use guidance.

Download **LivePhotoStudio-1.0-universal.dmg** and drag the app into Applications. The source archive and **SHA256SUMS.txt** are also provided. The package supports macOS 14+, Apple silicon, and Intel. It is ad-hoc signed and not notarized.

**Validation scope:** automated tests cover Live Photo pairing, timing, crop, rotation, watermarks, output files, and failure cleanup. The build workflow checks the universal package, Finder extension, resources, and signing status. The release uses synthetic media and local build validation, without device-specific compatibility claims.
