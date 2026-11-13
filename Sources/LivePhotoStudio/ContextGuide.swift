import SwiftUI

enum ContextGuideTarget: Hashable {
    case finishedActions
    case collageGenerate
}

struct ContextGuideTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [ContextGuideTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ContextGuideTarget: Anchor<CGRect>], nextValue: () -> [ContextGuideTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func contextGuideTarget(_ target: ContextGuideTarget) -> some View {
        anchorPreference(key: ContextGuideTargetPreferenceKey.self, value: .bounds) { [target: $0] }
    }
}

struct ContextGuideOverlay: View {
    let target: ContextGuideTarget
    let symbol: String
    let title: String
    let detail: String
    let anchors: [ContextGuideTarget: Anchor<CGRect>]
    let dismiss: () -> Void
    @State private var cardHeight: CGFloat = 190

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let focus = focusRect(in: proxy)
            let card = cardFrame(near: focus, in: bounds)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(bounds)
                    if !focus.isEmpty {
                        path.addRoundedRect(in: focus, cornerSize: CGSize(width: cornerRadius(focus), height: cornerRadius(focus)))
                    }
                }
                .fill(.black.opacity(0.66), style: FillStyle(eoFill: true))
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
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .shadow(color: .blue, radius: 7)
                        .position(x: focus.maxX - min(12, focus.width / 2), y: focus.minY + min(12, focus.height / 2))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: symbol).font(.title3).foregroundStyle(.blue)
                        Text(title).font(.headline)
                        Spacer(minLength: 8)
                    }
                    Text(detail).font(.body).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(UIStrings.isEnglish ? "Got it" : "知道了") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(18)
                .foregroundStyle(.primary)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
                .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                .frame(width: card.width)
                .position(x: card.midX, y: card.midY)
                .background {
                    GeometryReader { size in
                        Color.clear.preference(key: ContextGuideCardSizeKey.self, value: size.size)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(UIStrings.isEnglish ? "Feature guide" : "功能引导")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onExitCommand { dismiss() }
            .onPreferenceChange(ContextGuideCardSizeKey.self) { size in
                if size.height.isFinite, size.height > 0, abs(cardHeight - size.height) > 0.5 { cardHeight = size.height }
            }
        }
        .zIndex(100)
    }

    private func focusRect(in proxy: GeometryProxy) -> CGRect {
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
        if max(left, right) >= 260 {
            let width = min(idealWidth, max(left, right))
            let x = right >= left ? focus.maxX + gap : focus.minX - gap - width
            return CGRect(x: x, y: clamp(focus.midY - height / 2, safe.minY, safe.maxY - height), width: width, height: height)
        }
        let x = clamp(focus.midX - idealWidth / 2, safe.minX, safe.maxX - idealWidth)
        let below = safe.maxY - focus.maxY - gap
        let above = focus.minY - safe.minY - gap
        let y = below >= height ? focus.maxY + gap : (above >= height ? focus.minY - gap - height : (above > below ? safe.minY : safe.maxY - height))
        return CGRect(x: x, y: y, width: idealWidth, height: height)
    }
}

private struct ContextGuideCardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
