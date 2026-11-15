import SwiftUI

/// A menu with an explicit background so its visible right edge aligns with
/// the other controls in the inspector. The default Picker menu draws an
/// inset AppKit bezel, which made this row look shorter than its siblings.
struct PlaybackSpeedMenu: View {
    @Binding var selection: Double
    var enabled: Bool
    var language: String
    // Match the visible bezel height of the regular bordered controls. The
    // surrounding SwiftUI frame is 28pt, while AppKit draws the bezel at 24pt.
    private let controlHeight: CGFloat = 24

    private var title: String {
        selection == 1 ? L("正常 · 1×") : String(format: "%g×", selection)
    }

    var body: some View {
        ZStack {
            Menu {
            ForEach(MediaTiming.speeds, id: \.self) { speed in
                Button {
                    selection = speed
                } label: {
                    Text(speed == 1 ? L("正常 · 1×") : String(format: "%g×", speed))
                }
            }
            } label: {
                HStack(spacing: 6) {
                    Text(title).monospacedDigit()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(enabled ? Color.primary : Color.secondary)
            .allowsHitTesting(enabled)
            .id(language)
            .accessibilityLabel(L("播放速度"))
        }
        .frame(width: 116, height: controlHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlColor))
        )
        .opacity(enabled ? 1 : 0.55)
    }
}
