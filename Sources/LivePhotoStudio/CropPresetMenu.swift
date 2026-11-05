import SwiftUI
import AppKit

/// Native single-level menu: ratio diagrams remain visible in both menu and selection.
struct CropPresetMenu: NSViewRepresentable {
    @Binding var selection: CropPreset
    var sourceSize: CGSize
    var enabled: Bool
    var language: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let view = NSPopUpButton(frame: .zero, pullsDown: false)
        view.controlSize = .regular
        view.font = .systemFont(ofSize: NSFont.systemFontSize)
        view.target = context.coordinator
        view.action = #selector(Coordinator.choose(_:))
        view.setAccessibilityLabel(L("裁切比例"))
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateNSView(_ view: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let key = "\(sourceSize.width)/\(sourceSize.height)/\(language)"
        if context.coordinator.menuKey != key {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for preset in [CropPreset.original, .free, .square, .landscape43, .portrait34, .landscape32, .portrait23, .landscape169, .portrait916] {
                let item = NSMenuItem(title: L(preset == .original ? "原始比例" : preset.title), action: nil, keyEquivalent: "")
                item.representedObject = preset.rawValue
                item.image = Self.diagram(preset, sourceSize: sourceSize)
                menu.addItem(item)
            }
            view.menu = menu
            context.coordinator.menuKey = key
        }
        let value = selection == .off ? CropPreset.original : selection
        if let item = view.itemArray.first(where: { $0.representedObject as? String == value.rawValue }) { view.select(item) }
        view.isEnabled = enabled
        view.setAccessibilityLabel(L("裁切比例"))
    }
    private static func diagram(_ preset: CropPreset, sourceSize: CGSize) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { rect in
            let ratio = min(3, max(1 / 3, preset.aspect(in: sourceSize) ?? 1.35))
            let w = ratio >= 1 ? 16.0 : 14.0 * ratio
            let h = ratio >= 1 ? 16.0 / ratio : 14.0
            let box = NSRect(x: (rect.width - w) / 2, y: (rect.height - h) / 2, width: w, height: h)
            let path = NSBezierPath(roundedRect: box, xRadius: 1, yRadius: 1)
            path.lineWidth = 1.3
            if preset == .free { path.setLineDash([2, 1.6], count: 2, phase: 0) }
            NSColor.labelColor.setStroke(); path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
    final class Coordinator: NSObject {
        var parent: CropPresetMenu
        var menuKey = ""
        init(_ parent: CropPresetMenu) { self.parent = parent }
        @objc func choose(_ sender: NSPopUpButton) {
            guard let raw = sender.selectedItem?.representedObject as? String, let value = CropPreset(rawValue: raw) else { return }
            parent.selection = value
        }
    }
}
