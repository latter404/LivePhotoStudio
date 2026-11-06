import Foundation

/// Product strings only. Never pass filenames or user-entered watermark text here.
func L(_ chinese: String) -> String { UIStrings.text(chinese) }

enum UIStrings {
    static var isEnglish: Bool {
        switch UserDefaults.standard.string(forKey: "ui.language") ?? "system" {
        case "en": return true
        case "zh-Hans": return false
        default: return !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
        }
    }

    static func text(_ source: String) -> String {
        guard isEnglish else { return source }
        if let translated = translations[source] { return translated }
        guard source.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) else { return source }
        // Delivery and cleanup have separate outcomes. Translate both parts so
        // a successful export is not presented as failed when cleanup fails.
        let removedSuffix = " · 已移到废纸篓"
        if source.hasSuffix(removedSuffix) {
            return text(String(source.dropLast(removedSuffix.count))) + " · " + text("已移到废纸篓")
        }
        let cleanupFailure = " · 处理结果清理未完成："
        if let boundary = source.range(of: cleanupFailure) {
            return text(String(source[..<boundary.lowerBound])) + " · " + text("处理结果清理未完成") + ": "
                + text(String(source[boundary.upperBound...]))
        }
        let fullRange = NSRange(source.startIndex..., in: source)
        for (pattern, replacement) in compiledPatterns {
            if pattern.firstMatch(in: source, range: fullRange) != nil {
                return pattern.stringByReplacingMatches(in: source, range: fullRange, withTemplate: replacement)
            }
        }
        // Engine errors consist of a translated category plus an untranslated detail.
        for separator in [": ", "："] {
            if let boundary = source.range(of: separator) {
                let prefix = String(source[..<boundary.lowerBound]), detail = String(source[boundary.upperBound...])
                if let translated = translations[detail] { return (translations[prefix] ?? prefix) + ": " + translated }
            }
        }
        return source
    }

    private static let patterns: [(String, String)] = [
        (#"^已选 (\d+)/(\d+)$"#, "$1/$2 selected"),
        (#"^已添加 (\d+) 项到照片$"#, "Added $1 items to Photos"),
        (#"^已导出 (\d+) 项处理结果$"#, "Exported $1 processed items"),
        (#"^已旋转 (\d+)°$"#, "Rotated $1°"),
        (#"^已旋转 (\d+)° · 原画质导出不重新编码、不加黑边$"#, "Rotated $1° · Original video, no added borders"),
        (#"^正在生成 GIF · (\d+)/(\d+) 帧$"#, "Creating GIF · $1/$2 frames"),
        (#"^GIF 已导出 · ([\d.]+) 秒$"#, "GIF exported · $1 s"),
        (#"^已导出 · ([\d.]+) 秒 · 已按设置重新编码$"#, "Exported · $1 s · Re-encoded with your settings"),
        (#"^已导出 · ([\d.]+) 秒 · 视频未经重新编码$"#, "Exported · $1 s · Original video preserved"),
        (#"^起点 ([\d.]+) 秒，长度 ([\d.]+) 秒$"#, "Start $1 s, duration $2 s"),
        (#"^左侧 (\d+)%[，,]顶部 (\d+)%[，,]宽度 (\d+)%[，,]高度 (\d+)%$"#, "Left $1%, top $2%, width $3%, height $4%"),
        (#"^隔空投送未完成：(.*)$"#, "AirDrop did not complete: $1"),
        (#"^([\d]+ × [\d]+ · [\d.]+ fps · [\d.]+) 秒$"#, "$1 s"),
        (#"^(\d+) 秒$"#, "$1 s")
    ]

    private static let compiledPatterns: [(NSRegularExpression, String)] = patterns.compactMap { pattern, replacement in
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (expression, replacement)
    }

    private static let translations: [String: String] = [
        "速度": "Speed",
        "播放速度": "Playback speed",
        "正常 · 1×": "Normal · 1×",
        "输出时长": "Output duration",
        "变速会高质量重新编码；HDR 转为 SDR，声音保持音调。": "Speed changes re-encode at high quality. HDR becomes SDR; audio pitch is preserved.",
        "预估大小": "Estimated size",
        "文件大小": "File size",
        "估算中…": "Estimating…",
        "暂无法估算": "Unavailable",
        "抽样估算，仅供参考。画面变化可能影响体积，处理后显示实际大小。": "Sample-based estimate. Scene changes may affect size; the actual size appears after processing.",
        "播放速度必须在 0.25× 至 4× 之间。": "Speed must be between 0.25× and 4×.",
        "无法创建变速轨道": "Unable to create a speed-adjusted track",
        "输出路径与原视频相同，请选择其他位置。": "The output would replace the source video. Choose a different location.",
        "实况工坊":"LivePhoto Studio", "设置":"Settings", "文件":"File", "关于实况工坊":"About LivePhoto Studio",
        "外观":"Appearance", "语言":"Language", "跟随系统":"System", "浅色":"Light", "深色":"Dark",
        "退出实况工坊":"Quit LivePhoto Studio", "打开视频…":"Open Video…", "导出文件…":"Export Files…",
        "导出文件":"Export Files", "添加到照片":"Add to Photos", "照片＋视频":"Photo + Video", "开源许可":"Open-source Licenses",
        "实况工坊贡献者":"LivePhoto Studio contributors", "在 Mac 上制作实况照片与 GIF。":"Create Live Photos and GIFs on your Mac.",
        "采用 MIT 许可。部分代码基于 Revive，分享封装参考 makelive。第三方版权与许可随应用提供。":"MIT licensed. Parts of the code are based on Revive; sharing uses the format documented by makelive. Third-party notices are included.",
        "编辑设置":"Editing", "输出设置":"Output",
        "本次已处理":"Processed this session", "本次处理数量，重启后归零":"Items processed this session; resets when the app restarts",
        "画面":"Picture", "裁切":"Crop", "旋转":"Rotate", "输出":"Output", "格式":"Format", "画质":"Quality",
        "模式":"Mode", "附加":"Extras", "裁切比例":"Crop Ratio", "裁切尺寸":"Crop Size", "原始比例":"Original",
        "原比例":"Original", "不裁切":"Original", "自由":"Freeform", "原始":"Original", "原始尺寸":"Original Size",
        "原画质":"Original", "自定义":"Custom", "无损保留":"Original preserved", "完成裁切":"Done Cropping",
        "调整选框":"Adjust Crop", "重置裁切":"Reset Crop", "取消裁切，保留旋转":"Reset the crop and keep rotation",
        "向左旋转 90°":"Rotate Left 90°", "向右旋转 90°":"Rotate Right 90°",
        "向左旋转 90° · 不加黑边":"Rotate left 90° without adding borders", "向右旋转 90° · 不加黑边":"Rotate right 90° without adding borders",
        "导出格式":"Output Format", "导出模式":"Output Mode", "实况照片":"Live Photo", "GIF 动图":"GIF",
        "分辨率":"Resolution", "帧率":"Frame Rate", "编码":"Codec", "静音":"Mute", "文字水印":"Watermark",
        "输入水印文字":"Enter watermark text", "位置":"Position", "大小":"Size", "透明度":"Opacity",
        "右下":"Bottom Right", "左下":"Bottom Left", "右上":"Top Right", "左上":"Top Left", "居中":"Center",
        "水印大小百分比":"Watermark size percentage", "水印大小":"Watermark Size", "水印透明度":"Watermark Opacity",
        "占画面短边 · 自动记住":"Of the shorter edge · Saved automatically",
        "字体大小占画面短边的比例；长文字会自动缩小以放进画面。":"Text size as a percentage of the shorter edge. Long text shrinks to fit.",
        "高质量转码 · SDR":"High-quality encoding · SDR", "裁切需高质量转码 · SDR":"Crop requires encoding · SDR",
        "视频不重新编码":"Original video preserved", "水印需高质量转码 · SDR":"Watermark requires encoding · SDR",
        "原画质剪辑对齐关键帧，片段可能略长；封面为高质量 JPEG。裁切、添加水印或修改参数时重新编码。":"Original-quality cuts align to keyframes and may be slightly longer. The cover is a high-quality JPEG. Crop, watermark, or custom settings require encoding.",
        "256 色 · 无声音 · 最高 50 fps":"256 colors · No audio · Up to 50 fps",
        "默认保留原始尺寸，帧率随播放速度调整（上限 50 fps）。":"Keeps the original size. Frame rate follows playback speed, up to 50 fps.",
        "拖入视频":"Drop a Video", "也可按 ⌘O 选择文件":"Or press ⌘O to choose a file", "预览选区":"Preview Clip",
        "松开以导入视频":"Release to Import", "制作实况照片或 GIF 动图":"Create a Live Photo or animated GIF",
        "或点击选择文件":"or click to choose a file", "选择视频":"Choose a Video",
        "将视频拖入此处，或点击选择文件。":"Drop a video here, or click to choose a file.",
        "停止":"Stop", "3 秒":"3 s", "恢复 3 秒选区":"Reset to a 3-second selection", "时间轴":"Timeline", "全片":"Full Video",
        "重置为 3 秒":"Reset to 3 s", "将输出时长恢复为 3 秒；素材不足时使用可用长度。拖动选区两端可自定时长。":"Reset output to 3 seconds, or the available duration if shorter. Drag either selection edge to customize the duration.",
        "默认输出不超过 3 秒。拖动时间轴选区两端可自定时长；自定后切换速度会保留原视频选区。":"Output defaults to at most 3 seconds. Drag either selection edge to customize it; speed changes then preserve your source selection.",
        "导出为 JPG+MOV 文件…":"Export JPG + MOV Files…", "导出为 GIF 文件…":"Export GIF File…",
        "水印":"Watermark", "水印透明度百分比":"Watermark opacity percentage",
        "水印画质说明":"Watermark Quality",
        "添加水印会重新生成视频，无法保证完全无损。HDR 素材会转换为普通动态范围。":"Adding a watermark re-encodes the video, so lossless quality cannot be guaranteed. HDR footage is converted to standard dynamic range.",
        "裁切会重新生成视频；HDR 素材会转换为普通动态范围。":"Cropping re-encodes the video. HDR footage is converted to standard dynamic range.",
        "添加水印会重新生成视频；HDR 素材会转换为普通动态范围。":"Adding a watermark re-encodes the video. HDR footage is converted to standard dynamic range.",
        "默认保留原视频。添加水印、裁切或修改参数时会重新生成视频；HDR 素材会转换为普通动态范围。":"The original video is preserved by default. Adding a watermark, cropping, or changing settings re-encodes it and converts HDR footage to standard dynamic range.",
        "浏览":"Browse", "浏览长视频":"Browse Video", "视频选区":"Video Selection", "导出 GIF…":"Export GIF…",
        "导出实况…":"Export Files…", "隔空投送":"AirDrop", "隔空投送…":"AirDrop…", "添加 GIF 到照片":"Add GIF to Photos",
        "添加实况到照片":"Add Live Photo to Photos", "导出到这里":"Export Here",
        "裁切选框":"Crop Selection", "拖动以移动选框；四边和四角可调整大小":"Drag to move. Resize using the edges or corners.",
        "拖动调整大小":"Drag to resize", "向左移动":"Move Left", "向右移动":"Move Right", "向上移动":"Move Up", "向下移动":"Move Down",
        "左上角":"Top Left", "上边":"Top", "右上角":"Top Right", "右边":"Right", "右下角":"Bottom Right", "下边":"Bottom", "左下角":"Bottom Left", "左边":"Left",
        "裁切左上角":"Crop top-left corner", "裁切上边":"Crop top edge", "裁切右上角":"Crop top-right corner", "裁切右边":"Crop right edge",
        "裁切右下角":"Crop bottom-right corner", "裁切下边":"Crop bottom edge", "裁切左下角":"Crop bottom-left corner", "裁切左边":"Crop left edge",
        "所有处理都在本机完成":"All processing stays on this Mac", "拖动蓝色选区定位片段，拖动白色标记选择封面":"Drag the blue selection to choose a clip, and the white marker to choose its cover",
        "正在生成当前选区的实况预览…":"Preparing a Live Photo preview…", "实况已准备好 · 未保存到导出目录":"Live Photo ready · Not exported yet",
        "方向已更新 · 保留当前裁切范围":"Rotation updated · Crop preserved", "方向已更新 · 文字水印将高质量重新编码":"Rotation updated · Watermark requires encoding",
        "已恢复原始方向 · 视频原画质":"Original orientation restored · Original video quality", "已取消导出":"", "已取消隔空投送":"",
        "正在生成实况照片…":"Creating Live Photo…", "正在生成 GIF…":"Creating GIF…", "已按设置重新编码":"Re-encoded with your settings",
        "视频未经重新编码":"Original video preserved", "正在生成当前选区并准备隔空投送…":"Preparing the clip for AirDrop…",
        "请在隔空投送窗口选择你的 iPhone":"Choose your iPhone in the AirDrop window", "正在准备添加当前选区到照片…":"Preparing the clip for Photos…",
        "请在系统设置中允许添加照片。":"Allow this app to add photos in System Settings.", "当前选区已添加到「照片」":"Added to Photos",
        "正在准备 GIF 隔空投送…":"Preparing GIF for AirDrop…", "请在隔空投送窗口选择接收设备":"Choose a device in the AirDrop window",
        "正在添加 GIF 到照片…":"Adding GIF to Photos…", "GIF 已添加到「照片」":"GIF added to Photos",
        "隔空投送窗口已关闭 · 发送结果请以系统窗口和接收设备为准":"AirDrop closed · Check the receiving device for the result",
        "文件中没有视频轨道":"No video track found", "读取失败":"Could not read", "导出失败":"Export failed", "封面生成失败":"Could not create cover", "已取消":"Cancelled",
        "视频时间范围无效":"Invalid video time range", "选区不在视频范围内":"The selection is outside the video",
        "此编码无法无损封装，请主动选择自定义模式。":"This codec cannot be copied without encoding. Choose Custom mode.",
        "音轨的采样率或声道信息无效。可以开启静音后重试。":"Invalid audio sample rate or channel information. Try again with Mute enabled.",
        "这段多声道音频缺少声道布局，无法导出。可以开启静音后重试。":"The multichannel audio has no channel layout. Try again with Mute enabled.",
        "这段音频的声道布局或编码暂不支持导出。可以开启静音后重试。":"This audio codec or channel layout is unsupported. Try again with Mute enabled.",
        "系统编码器不支持这段视频的输出参数。":"The system encoder does not support these video settings.",
        "读取已中止":"Reading stopped", "写入已中止":"Writing stopped", "写入未完成":"Writing did not complete",
        "实况时间信息写入失败":"Could not write Live Photo timing", "媒体样本写入失败":"Could not write media samples",
        "裁切范围无效":"Invalid crop region", "生成结果未通过配对校验":"The generated photo and video did not pass pairing checks",
        "视频尺寸或方向信息无效。":"Invalid video size or orientation", "导出时间范围、尺寸或帧率无效":"Invalid export range, size, or frame rate",
        "视频画面尺寸无效或超出支持范围":"Invalid or unsupported video dimensions", "裁切区域至少需要 2 × 2 像素":"The crop must be at least 2 × 2 pixels",
        "4K 以上的自定义导出请选择 HEVC 编码。":"Choose HEVC for custom exports above 4K.", "视频帧率无效":"Invalid video frame rate",
        "无法创建转码任务":"Could not create encoding task", "转码失败":"Encoding failed", "无法创建旋转轨道":"Could not create rotation track",
        "GIF 时间范围或帧率无效":"Invalid GIF range or frame rate", "GIF 片段过长":"The GIF clip is too long",
        "无法裁切 GIF 画面":"Could not crop GIF frame", "无法缩放裁切画面":"Could not resize cropped frame", "无法读取裁切画面":"Could not read cropped frame",
        "无法创建 GIF":"Could not create GIF", "GIF 尺寸超出格式限制":"GIF dimensions exceed format limits", "GIF 帧尺寸不一致":"GIF frames have inconsistent dimensions",
        "无法创建 GIF 帧":"Could not create GIF frame", "GIF 帧编码失败":"Could not encode GIF frame", "GIF 没有画面":"The GIF has no frames",
        "系统返回了无效 GIF 帧":"The system returned an invalid GIF frame", "同名文件已存在，请重新导出。":"A file with this name already exists. Export again.",
        "实况文件不完整或配对校验失败，请重新导出。":"The Live Photo files are incomplete or do not match. Export again.",
        "分享包已存在，请重试。":"The share package already exists. Try again.", "请先完成或取消当前隔空投送。":"Finish or cancel the current AirDrop first.",
        "当前系统无法启动隔空投送，请检查设备设置后重试。":"AirDrop is unavailable. Check device settings and try again.", "当前系统无法启动隔空投送。":"AirDrop is unavailable.",
        "实况照片预览":"Live Photo Preview", "完成":"Done", "播放实况":"Play Live Photo", "系统无法加载这组实况文件，请重新导出。":"The system could not load this Live Photo. Export again.",
        "正在加载实况…":"Loading Live Photo…", "这里播放的是按当前选区和设置生成的实况。关闭预览后可直接点击「隔空投送」，发送完整实况包到 iPhone。":"This preview uses the current clip and settings. Close it and choose AirDrop to send the Live Photo to iPhone.",
        "显示导出诊断记录":"Show Export Diagnostics",
        "将 GIF 添加到照片图库":"Add the GIF to your Photos library",
        "作为一张实况照片添加到照片图库":"Add it to your Photos library as a Live Photo",
        "保存 GIF 文件":"Save a GIF file",
        "保存照片和视频两个配对文件；在 Finder 中它们会分开显示":"Save a paired photo and video. Finder displays them as separate files.",
        "时间轴显示范围":"Timeline range",

        "处理":"Process", "正在处理…":"Processing…", "已完成处理":"Processing complete",
        "已处理":"Processed", "已处理…":"Processed…", "查看和选择处理结果":"View and select processed items",
        "将所选处理结果添加到照片":"Add selected items to Photos", "发送所选处理结果":"Send selected items",
        "导出所选处理结果":"Export selected items", "选择处理结果":"Select Processed Item",
        "还没有处理结果":"No Processed Items", "选好片段后点击「处理」，处理结果会保存在这里。":"Choose a clip and click Process. Your processed items will appear here.",
        "全选":"Select All", "取消全选":"Deselect All", "移除":"Remove", "文件不可用":"File Unavailable",
        "处理结果保存在本机，关闭窗口后仍会保留。":"Processed items stay on this Mac when you close the window.",
        "无法预览此处理结果":"This item could not be previewed", "预览 GIF":"Preview GIF", "停止预览":"Stop Preview",
        "存储与清理":"Storage & Cleanup", "存储与清理…":"Storage & Cleanup…", "使用引导…":"Show Guide…",
        "自动删除处理结果":"Automatically Remove Processed Items", "添加到照片后":"After Adding to Photos",
        "隔空投送后":"After AirDrop", "导出文件后":"After Exporting Files",
        "成功添加到照片后，将所选处理结果移到废纸篓。":"Move selected processed items to the Trash after they are successfully added to Photos.",
        "投送窗口关闭后，确认接收成功再清理处理结果。":"After the AirDrop window closes, confirm receipt before removing the items.",
        "已确认接收成功？":"Have you confirmed receipt?",
        "macOS 不会可靠地区分投送完成与取消。确认接收设备已收到后，再将本次处理结果移到废纸篓。":"macOS does not reliably distinguish completed transfers from cancellation. Confirm the receiving device has your items before moving these processed copies to the Trash.",
        "保留结果":"Keep Items", "移到废纸篓":"Move to Trash",
        "成功导出文件后，将所选处理结果移到废纸篓。":"Move selected processed items to the Trash after the files are successfully exported.",
        "只清理应用内处理结果，不影响原视频、照片图库或导出的文件。":"Only items in this app are removed. Source videos, your Photos library and exported files are kept.",
        "保存位置":"Save Location", "更改…":"Change…", "选择位置":"Choose Location",
        "部分处理结果无法读取，可在列表中移除。":"Some processed items could not be read. You can remove them from the list.",
        "正在添加处理结果到照片…":"Adding processed items to Photos…", "已添加 1 项到照片":"Added 1 item to Photos",
        "正在准备批量隔空投送…":"Preparing selected items for AirDrop…",
        "正在导出处理结果…":"Exporting processed items…", "已导出 1 项处理结果":"Exported 1 processed item",
        "已移到废纸篓":"Moved to Trash", "处理结果清理未完成":"Processed item cleanup did not complete",
        "正在移动处理结果…":"Moving processed items…", "保存位置已更新":"Save location updated",
        "保存位置已更新，旧位置副本尚未清理。":"Save location updated. Copies in the old location have not been removed.",
        "新保存位置不能位于当前处理结果文件夹内。":"Choose a location outside the current processed items folder.",
        "新位置已有不同内容的同名处理结果，未更改保存位置。":"The new location already contains a different item with the same name. The save location was not changed.",
        "无法生成处理结果缩略图。":"Could not create the thumbnail.", "处理结果文件不完整或信息无效。":"Processed item files are incomplete or invalid.",
        "处理结果文件不存在或无法读取。":"A processed item file is missing or unreadable.",
        "请选择完整且不重复的处理结果。":"Select complete items without duplicates.",
        "请选择有效的导出文件夹。":"Choose a valid export folder.",
        "导出位置不能在处理结果保存文件夹内，请选择其他文件夹。":"Choose an export location outside the processed items folder.",
        "无法创建不重名的导出文件，请更换文件夹。":"Could not create export files with unique names. Choose another folder.",
        "请选择至少一项处理结果。":"Select at least one processed item.",
        "分享目录已存在，请重试。":"The sharing folder already exists. Try again."
    ]
}
