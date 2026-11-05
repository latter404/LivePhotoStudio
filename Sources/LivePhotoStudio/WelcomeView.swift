import SwiftUI

/// Only replaces the empty left-hand preview; the existing inspector stays visible.
struct WelcomeView: View {
    @Bindable var model: Model
    let dropTargeted: Bool
    @State private var hovering = false

    var body: some View {
        Button { model.choose() } label: {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.badge.plus")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 76, height: 76)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(L(dropTargeted ? "松开以导入视频" : "拖入视频"))
                        .font(.system(size: 23, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                VStack(spacing: 12) {
                    Text(L("或点击选择文件"))
                        .font(.callout).foregroundStyle(.secondary)
                    Text("⌘ O")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(dropTargeted ? 0.09 : hovering ? 0.035 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(dropTargeted ? Color.accentColor : Color.primary.opacity(hovering ? 0.28 : 0.16),
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [7, 5]))
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(model.busy)
        .onHover { hovering = $0 }
        .accessibilityLabel(L("选择视频"))
        .accessibilityHint(L("将视频拖入此处，或点击选择文件。"))
    }
}
