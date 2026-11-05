import SwiftUI

enum GuideTarget: Hashable {
    case importVideo, process, collection, delivery
}

struct GuideTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [GuideTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [GuideTarget: Anchor<CGRect>], nextValue: () -> [GuideTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func guideTarget(_ target: GuideTarget) -> some View {
        anchorPreference(key: GuideTargetPreferenceKey.self, value: .bounds) { [target: $0] }
    }
}

private struct GuidePage {
    let target: GuideTarget
    let symbol: String
    let title: String
    let detail: String

    static var pages: [GuidePage] {
        let english = UIStrings.isEnglish
        return [
            GuidePage(target: .importVideo, symbol: "film", title: english ? "Choose a clip" : "选一段画面",
                detail: english ? "Drop in a video, then drag the timeline selection to choose your clip and cover frame." : "拖入视频，在时间轴上拖动选框，选好片段和封面。"),
            GuidePage(target: .process, symbol: "sparkles", title: english ? "Process and keep creating" : "处理并累积",
                detail: english ? "Adjust your settings and click Process. Your clip is saved separately, so you can move on to the next one." : "调整好设置后点「处理」。当前片段会单独保存，你可以继续剪下一段。"),
            GuidePage(target: .collection, symbol: "square.stack", title: english ? "Choose processed items" : "选择处理结果",
                detail: english ? "Click Processed to browse this session’s results and your history. Preview items or select several to use together." : "点击「已处理」查看本次和历史结果。可逐张预览，也可多选后一起操作。"),
            GuidePage(target: .delivery, symbol: "square.and.arrow.up", title: english ? "Use your selection" : "统一操作",
                detail: english ? "Add to Photos, AirDrop and Export all use the selected items. Automatic deletion is off by default; set it separately for each action in Storage & Cleanup." : "添加到照片、隔空投送和导出文件，都作用于已选处理结果。自动删除默认关闭，可在「存储与清理」里分别开启。")
        ]
    }
}

private struct GuideCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// A SwiftUI overlay rather than a modal sheet. The even-odd cutout reveals the
/// actual control; a full rectangular hit region prevents interaction beneath it,
/// including the embedded native video view. No timers or repeating animations.
struct GuideOverlay: View {
    @Bindable var model: Model
    let anchors: [GuideTarget: Anchor<CGRect>]
    @State private var cardHeight: CGFloat = 220

    var body: some View {
        if let current = model.guideStep {
            let pages = GuidePage.pages
            let step = min(max(0, current), pages.count - 1)
            let page = pages[step]
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let focus = focusRect(for: page.target, proxy: proxy)
                let card = cardFrame(near: focus, in: bounds)
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.addRect(bounds)
                        if !focus.isEmpty { path.addRoundedRect(in: focus, cornerSize: CGSize(width: cornerRadius(focus), height: cornerRadius(focus))) }
                    }
                    .fill(.black.opacity(0.66), style: FillStyle(eoFill: true))
                    // The spotlight is visually transparent but not interactive.
                    .contentShape(Rectangle())
                    .onTapGesture { }
                    .accessibilityHidden(true)

                    if !focus.isEmpty {
                        RoundedRectangle(cornerRadius: cornerRadius(focus))
                            .stroke(.white.opacity(0.9), lineWidth: 1.5)
                            .shadow(color: .blue.opacity(0.75), radius: 9)
                            .frame(width: focus.width, height: focus.height)
                            .position(x: focus.midX, y: focus.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        Circle().fill(.white)
                            .frame(width: 7, height: 7)
                            .shadow(color: .blue, radius: 7)
                            .position(x: focus.maxX - min(12, focus.width / 2), y: focus.minY + min(12, focus.height / 2))
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    explanation(page: page, step: step, count: pages.count)
                        .frame(width: card.width)
                        .background {
                            GeometryReader { size in
                                Color.clear.preference(key: GuideCardSizeKey.self, value: size.size)
                            }
                        }
                        .position(x: card.midX, y: card.midY)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .onPreferenceChange(GuideCardSizeKey.self) { size in
                    if size.height.isFinite, size.height > 0, abs(cardHeight - size.height) > 0.5 { cardHeight = size.height }
                }
                .onExitCommand { model.finishGuide() }
            }
            .zIndex(100)
        }
    }

    private func explanation(page: GuidePage, step: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: page.symbol).font(.title3).foregroundStyle(.blue)
                Text(page.title).font(.headline)
                Spacer(minLength: 8)
                Text("\(step + 1) / \(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(page.detail).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(UIStrings.isEnglish ? "Skip" : "跳过") { model.finishGuide() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                Spacer()
                Button(UIStrings.isEnglish ? (step == count - 1 ? "Done" : "Next") : (step == count - 1 ? "完成" : "下一步")) {
                    if step == count - 1 { model.finishGuide() }
                    else { model.guideStep = step + 1 }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .foregroundStyle(.primary)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(UIStrings.isEnglish ? "Guide, step \(step + 1) of \(count)" : "使用引导，第 \(step + 1) 步，共 \(count) 步")
    }

    private func focusRect(for target: GuideTarget, proxy: GeometryProxy) -> CGRect {
        guard let anchor = anchors[target] else { return .zero }
        let raw = proxy[anchor]
        guard [raw.minX, raw.minY, raw.width, raw.height].allSatisfy(\.isFinite), raw.width > 0, raw.height > 0 else { return .zero }
        let visible = CGRect(origin: .zero, size: proxy.size).insetBy(dx: 5, dy: 5)
        let clipped = raw.insetBy(dx: -6, dy: -6).intersection(visible)
        return clipped.isNull ? .zero : clipped
    }

    private func cornerRadius(_ rect: CGRect) -> CGFloat { min(14, min(rect.width, rect.height) / 2) }

    private func cardFrame(near focus: CGRect, in bounds: CGRect) -> CGRect {
        let safe = bounds.insetBy(dx: 18, dy: 18)
        let gap: CGFloat = 18
        let idealWidth = min(320, max(1, safe.width))
        let height = min(cardHeight, max(1, safe.height))
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), max(low, high)) }
        guard !focus.isEmpty else {
            return CGRect(x: safe.midX - idealWidth / 2, y: safe.midY - height / 2, width: idealWidth, height: height)
        }
        let right = safe.maxX - focus.maxX - gap
        let left = focus.minX - safe.minX - gap
        // The narrowest supported window still leaves room for a readable card
        // beside a large preview. Prefer a side over obscuring the highlighted UI.
        if max(left, right) >= 260 {
            let width = min(idealWidth, max(left, right))
            let x = right >= left ? focus.maxX + gap : focus.minX - gap - width
            return CGRect(x: x, y: clamp(focus.midY - height / 2, safe.minY, safe.maxY - height), width: width, height: height)
        }
        let x = clamp(focus.midX - idealWidth / 2, safe.minX, safe.maxX - idealWidth)
        let below = safe.maxY - focus.maxY - gap
        let above = focus.minY - safe.minY - gap
        let y: CGFloat
        if below >= height { y = focus.maxY + gap }
        else if above >= height { y = focus.minY - gap - height }
        else { y = above > below ? safe.minY : safe.maxY - height }
        return CGRect(x: x, y: y, width: idealWidth, height: height)
    }
}
