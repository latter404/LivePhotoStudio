import SwiftUI

/// All editing and output controls live together; the preview stays unobstructed.
struct EditorInspector: View {
    @Bindable var model: Model
    @State private var estimate: GIFSizeEstimate?
    @State private var estimatedRecipe: GIFRecipe?
    @State private var estimateFailed = false
    private var estimateRecipe: GIFRecipe? { model.gifMode && !model.busy ? model.currentGIFRecipe : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup {
                picture
                Divider().padding(.vertical, 2)
                watermark
            }
            settingsGroup {
                output
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.busy)
        .task(id: estimateRecipe) {
            estimate = nil; estimatedRecipe = nil; estimateFailed = false
            guard let recipe = estimateRecipe, model.lastGIFSize?.recipe != recipe else { return }
            do {
                try await Task.sleep(for: .milliseconds(900))
                let result = try await GIFSizeEstimator.shared.estimate(recipe)
                try Task.checkCancellation()
                estimate = result; estimatedRecipe = recipe
            } catch {
                if !Task.isCancelled { estimateFailed = true }
            }
        }
    }

    private var picture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                heading("编辑设置", symbol: "crop.rotate")
                Spacer()
                if model.quarterTurns != 0 {
                    Text("\(model.quarterTurns * 90)°").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                fieldLabel("裁切", symbol: "crop")
                Text(verbatim: model.url == nil ? "—" : "\(Int(model.outputDisplaySize.width))×\(Int(model.outputDisplaySize.height))")
                    .font(.system(size:11,design:.monospaced)).fixedSize().foregroundStyle(.secondary)
                    .accessibilityLabel(L("裁切尺寸"))
                    .accessibilityValue("\(Int(model.outputDisplaySize.width)) × \(Int(model.outputDisplaySize.height))")
                Spacer(minLength: 0)
                CropPresetMenu(selection: Binding(get: {model.cropPreset}, set: {model.setCropPreset($0)}),
                    sourceSize: model.orientedDisplaySize, enabled: !model.busy && model.url != nil,
                    language: AppPreferences.shared.language.rawValue)
                    .frame(width: 108, height: 24)
                    .help(L("裁切会重新生成视频；HDR 素材会转换为普通动态范围。"))
                Button { model.cropEditing.toggle() } label: {
                    Image(systemName: model.cropEditing ? "checkmark" : "crop")
                        .font(.system(size: 14))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered).controlSize(.regular).frame(height: 24)
                .tint(model.cropEditing ? .accentColor : nil)
                .accessibilityLabel(L(model.cropEditing ? "完成裁切" : "调整选框"))
                .help(L(model.cropEditing ? "完成裁切" : "调整选框"))
            }
            HStack(spacing: 12) {
                fieldLabel("旋转", symbol: "rotate.right")
                HStack(spacing: 8) {
                    Button { model.rotate(-1) } label: {
                        Label("90°", systemImage: "rotate.left").frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel(L("向左旋转 90°")).help(L("向左旋转 90° · 不加黑边"))
                    Button { model.rotate(1) } label: {
                        Label("90°", systemImage: "rotate.right").frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel(L("向右旋转 90°")).help(L("向右旋转 90° · 不加黑边"))
                }
                .buttonStyle(.bordered).controlSize(.regular)
            }
            HStack {
                fieldLabel("速度", symbol: "speedometer")
                Spacer()
                Picker(L("播放速度"), selection: Binding(get: { model.speed }, set: { model.setSpeed($0) })) {
                    ForEach(MediaTiming.speeds, id: \.self) { speed in
                        Text(speed == 1 ? L("正常 · 1×") : String(format: "%g×", speed)).tag(speed)
                    }
                }.labelsHidden().frame(width: 116)
            }
            HStack {
                fieldLabel("输出时长", symbol: "clock")
                Spacer()
                Text(String(format: "%.2f s", model.outputDuration)).monospacedDigit()
            }.help(L("默认输出不超过 3 秒。拖动时间轴选区两端可自定时长；自定后切换速度会保留原视频选区。"))
            if model.speed != 1 {
                if !model.gifMode {
                    Text(L("变速会高质量重新编码；HDR 转为 SDR，声音保持音调。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .disabled(model.url == nil)
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("输出设置", symbol: "square.and.arrow.up")
            HStack(spacing: 12) {
                fieldLabel("格式", symbol: "photo.stack")
                Picker(L("导出格式"), selection: $model.gifMode) {
                    Text(L("实况照片")).tag(false)
                    Text(L("GIF 动图")).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
            }

            if model.gifMode {
                HStack(spacing: 12) {
                    fieldLabel("模式", symbol: "slider.horizontal.3")
                    Picker(L("导出模式"), selection: $model.gifCustom) {
                        Text(L("原始尺寸")).tag(false)
                        Text(L("自定义")).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
                if model.gifCustom {
                    optionSlider("分辨率", selection: $model.gifEdge, values: [480,720,1080,1920,2560,3840,7680,0], labels: ["480","720","1080","1920","2K","4K","8K","原始"])
                    optionSlider("帧率", selection: $model.gifFPS, values: [10,15,24,25,30,50,0], labels: ["10","15","24","25","30","50","原始"])
                }
                Text(L("256 色 · 无声音 · 最高 50 fps"))
                    .font(.caption).foregroundStyle(.secondary)
                    .help(L("默认保留原始尺寸，帧率随播放速度调整（上限 50 fps）。"))
                HStack {
                    fieldLabel(model.lastGIFSize?.recipe == model.currentGIFRecipe && model.lastGIFSize != nil ? "文件大小" : "预估大小", symbol: "doc")
                    Spacer()
                    Text(gifSizeText).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .help(L("抽样估算，仅供参考。画面变化可能影响体积，处理后显示实际大小。"))
            } else {
                HStack(spacing: 12) {
                    fieldLabel("画质", symbol: "sparkles")
                    Picker(L("导出模式"), selection: $model.custom) {
                        Text(L(model.activeWatermark == nil && model.activeCrop == nil && model.speed == 1 ? "原画质" : "原始尺寸")).tag(false)
                        Text(L("自定义")).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                    .help(L("默认保留原视频。添加水印、裁切或修改参数时会重新生成视频；HDR 素材会转换为普通动态范围。"))
                }
                if model.custom {
                    optionSlider("分辨率", selection: $model.edge, values: [854,1280,1920,2560,3840,7680,0], labels: ["480p","720p","1080p","2K","4K","8K","原始"])
                    optionSlider("帧率", selection: $model.fps, values: [24,25,30,50,60,0], labels: ["24","25","30","50","60","原始"])
                    HStack {
                        fieldLabel("编码", symbol: "film")
                        Spacer()
                        Picker(L("编码"), selection: $model.hevc) {
                            Text("HEVC").tag(true); Text("H.264").tag(false)
                        }.labelsHidden()
                    }
                }
            }
        }
    }

    private var gifSizeText: String {
        guard let recipe = model.currentGIFRecipe else { return "—" }
        if let actual = model.lastGIFSize, actual.recipe == recipe {
            return ByteCountFormatter.string(fromByteCount: actual.bytes, countStyle: .file)
        }
        if let estimate, estimatedRecipe == recipe {
            return "≈ " + ByteCountFormatter.string(fromByteCount: estimate.bytes, countStyle: .file)
        }
        return L(estimateFailed ? "暂无法估算" : model.busy ? "—" : "估算中…")
    }

    private var watermark: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.gifMode {
                HStack {
                    fieldLabel("静音", symbol: "speaker.slash")
                    Spacer()
                    Toggle(L("静音"), isOn: $model.mute).labelsHidden().toggleStyle(.switch).tint(.accentColor).controlSize(.mini)
                }
            }
            HStack {
                fieldLabel("水印", symbol: "signature")
                Spacer()
                Toggle(L("水印"), isOn: $model.watermarkEnabled)
                    .labelsHidden().toggleStyle(.switch).tint(.accentColor).controlSize(.mini)
                    .help(L("添加水印会重新生成视频；HDR 素材会转换为普通动态范围。"))
            }

            if model.watermarkEnabled {
                Picker(L("水印类型"), selection: $model.watermark.imageMode) {
                    Text(L("文字")).tag(false)
                    Text(L("图片")).tag(true)
                }.pickerStyle(.segmented)
                if model.watermark.imageMode {
                    HStack(spacing: 8) {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        Text(model.watermark.displayName.isEmpty ? L("未选择图片") : model.watermark.displayName)
                            .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("选择图片")) { model.chooseWatermarkImage() }
                        if model.watermark.imagePath != nil {
                            Button(L("移除"), role: .destructive) { model.removeWatermarkImage() }
                        }
                    }.font(.callout)
                    if model.watermark.imagePath != nil && !model.watermark.imageAvailable {
                        Text(L("图片水印文件不可用，请重新选择图片"))
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    TextField(L("输入水印文字"), text: $model.watermark.text)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.watermark.text) { _, value in
                            if value.count > 120 { model.watermark.text = String(value.prefix(120)) }
                        }
                }
                HStack {
                    fieldLabel("位置", symbol: "viewfinder")
                    Spacer()
                    Picker(L("位置"), selection: $model.watermark.position) {
                        Text(L("右下")).tag(0); Text(L("左下")).tag(1); Text(L("右上")).tag(2)
                        Text(L("左上")).tag(3); Text(L("居中")).tag(4)
                        Text(UIStrings.isEnglish ? "Free" : "自由").tag(5)
                    }.labelsHidden()
                }
                watermarkSlider("大小", symbol: "ruler", value: $model.watermarkPercent,
                    range: 2...10, decimals: 1, accessibility: "水印大小百分比")
                watermarkSlider("透明度", symbol: "circle.lefthalf.filled", value: $model.watermarkOpacityPercent,
                    range: 15...100, decimals: 0, accessibility: "水印透明度百分比")
                Text(L("添加水印会重新生成视频，无法保证完全无损。HDR 素材会转换为普通动态范围。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func watermarkSlider(_ title: String, symbol: String, value: Binding<Double>,
                                 range: ClosedRange<Double>, decimals: Int, accessibility: String) -> some View {
        HStack(spacing: 8) {
            fieldLabel(title, symbol: symbol).frame(width: 76, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(L(accessibility))
            HStack(spacing: 4) {
                TextField(L(title), value: value, format: .number.precision(.fractionLength(decimals)))
                    .multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                    .frame(width: 44).accessibilityLabel(L(accessibility))
                Text("%").foregroundStyle(.secondary)
            }.frame(width: 60, alignment: .trailing)
        }
    }

    private func fieldLabel(_ title: String, symbol: String) -> some View {
        Label { Text(L(title)).fixedSize() } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
        }
    }

    private func heading(_ title: String, symbol: String) -> some View {
        Label {
            Text(L(title))
        } icon: {
            Image(systemName: symbol).frame(width: 18)
        }
        .font(.title2.weight(.semibold))
        .foregroundStyle(.primary)
        .accessibilityAddTraits(.isHeader)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func optionSlider(_ title: String, selection: Binding<Int>, values: [Int], labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                fieldLabel(title, symbol: title == "帧率" ? "film" : "arrow.up.left.and.arrow.down.right")
                Spacer()
                Text(L(labels[values.firstIndex(of: selection.wrappedValue) ?? values.count - 1]) + (title == "帧率" && selection.wrappedValue != 0 ? " fps" : ""))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            Slider(value: Binding(get: {
                Double(values.firstIndex(of: selection.wrappedValue) ?? values.count - 1)
            }, set: {
                selection.wrappedValue = values[min(values.count - 1, max(0, Int($0.rounded())))]
            }), in: 0...Double(values.count - 1), step: 1).accessibilityLabel(L(title))
            GeometryReader { geometry in
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(L(label)).font(.system(size: 10)).foregroundStyle(.secondary)
                        .position(x: 9 + (geometry.size.width - 18) * Double(index) / Double(labels.count - 1), y: 6)
                }
            }.frame(height: 12)
        }
    }
}
