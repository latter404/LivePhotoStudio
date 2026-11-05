import AppKit
import SwiftUI

/// SwiftUI owns the menu hierarchy and native Quit action. AppKit only hides
/// unused menu headings and supplies hidden responder-chain editing shortcuts.
@MainActor final class AppMenuController: NSObject, NSMenuItemValidation {
    static let shared = AppMenuController()
    private var aboutPanel: NSPanel?
    private var licensePanel: NSPanel?
    private var openMainWindow: (() -> Void)?

    func setOpenWindowHandler(_ action: @escaping () -> Void) { openMainWindow = action }

    func refresh() {
        if let panel = aboutPanel, panel.title != L("关于实况工坊") {
            panel.close(); aboutPanel = nil
            licensePanel?.close(); licensePanel = nil
        }
        pruneMenus()
    }

    func ensureInstalled() { pruneMenus() }

    func pruneMenus() {
        guard let main = NSApp.mainMenu else { return }
        let unused = Set(["File", "文件", "Edit", "编辑", "View", "显示", "视图", "Window", "窗口", "Help", "帮助"])
        for entry in main.items.dropFirst() where unused.contains(entry.title) {
            // Preserve the hierarchy SwiftUI owns; removing headings can invalidate
            // its menu bookkeeping when the environment changes or the app idles.
            entry.isHidden = true
        }
        guard let host = main.items.first?.submenu else { return }
        // Move only our own legacy shortcut entries; leave SwiftUI's hierarchy
        // intact. A visible app-menu parent keeps hidden key equivalents active.
        for entry in main.items.dropFirst() {
            guard let menu = entry.submenu else { continue }
            for item in menu.items where item.identifier?.rawValue.hasPrefix("livephoto.shortcut.") == true {
                menu.removeItem(item)
            }
        }
        // These are ordinary AppKit responder actions, independent of SwiftUI's
        // menu targets. The items stay hidden, but their shortcuts remain usable.
        for (title, selector, key, shift) in [
            ("Cut", "cut:", "x", false), ("Copy", "copy:", "c", false),
            ("Paste", "paste:", "v", false), ("Select All", "selectAll:", "a", false),
            ("Undo", "undo:", "z", false), ("Redo", "redo:", "z", true),
            ("Close", "performClose:", "w", false)
        ] {
            let identifier = NSUserInterfaceItemIdentifier("livephoto.shortcut." + selector)
            guard !host.items.contains(where: { $0.identifier == identifier }) else { continue }
            let command = NSMenuItem(title: title, action: NSSelectorFromString(selector), keyEquivalent: key)
            command.identifier = identifier
            command.target = nil
            command.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            command.isHidden = true
            command.allowsKeyEquivalentWhenHidden = true
            host.addItem(command)
        }
        for (title, selector, key, shift) in [
            ("Open Video", #selector(openVideo), "o", false),
            ("Process", #selector(processCurrent), "p", false),
            ("Processed", #selector(showFinished), "p", true),
            ("Export Processed Items", #selector(exportFinished), "e", false)
        ] {
            let identifier = NSUserInterfaceItemIdentifier("livephoto.shortcut." + NSStringFromSelector(selector))
            guard !host.items.contains(where: { $0.identifier == identifier }) else { continue }
            let command = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            command.identifier = identifier
            command.target = self
            command.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            command.isHidden = true
            command.allowsKeyEquivalentWhenHidden = true
            host.addItem(command)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        if Model.shared.guideStep != nil,
           [#selector(openVideo), #selector(processCurrent), #selector(showFinished), #selector(exportFinished)].contains(action) { return false }
        switch action {
        case #selector(openVideo): return !Model.shared.busy
        case #selector(processCurrent): return Model.shared.url != nil && !Model.shared.busy && Model.shared.finishedLoaded
        case #selector(exportFinished): return !Model.shared.selectedFinished.isEmpty && !Model.shared.busy
        default: return true
        }
    }

    @objc private func openVideo() {
        guard !Model.shared.busy, Model.shared.guideStep == nil else { return }
        openMainWindow?()
        Task { @MainActor in await Task.yield(); Model.shared.choose() }
    }
    @objc private func processCurrent() { guard Model.shared.guideStep == nil else { return }; Model.shared.processCurrent() }
    @objc private func showFinished() { guard Model.shared.guideStep == nil else { return }; openMainWindow?(); Model.shared.showFinished = true }
    @objc private func exportFinished() { guard Model.shared.guideStep == nil else { return }; Model.shared.exportFinished() }

    @objc func showAbout() {
        if let aboutPanel { aboutPanel.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 310), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = L("关于实况工坊")
        panel.isReleasedWhenClosed = false
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setContentHuggingPriority(.required, for: .vertical)
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true
        content.addArrangedSubview(icon)
        let name = label(L("实况工坊"), size: 21, weight: .semibold)
        content.addArrangedSubview(name)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let versionLabel = label(version, size: 12)
        versionLabel.toolTip = UIStrings.isEnglish ? "Build \(build)" : "构建 \(build)"
        versionLabel.textColor = .secondaryLabelColor
        content.addArrangedSubview(versionLabel)
        content.addArrangedSubview(label(L("在 Mac 上制作实况照片与 GIF。"), size: 13))
        let copyright = label("© 2026 latter404", size: 11)
        copyright.textColor = .secondaryLabelColor
        content.addArrangedSubview(copyright)
        let licenses = NSButton(title: L("开源许可"), target: self, action: #selector(showLicenses))
        licenses.bezelStyle = .rounded
        content.addArrangedSubview(licenses)
        panel.contentView?.addSubview(content)
        if let host = panel.contentView {
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 28),
                content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -28),
                content.topAnchor.constraint(equalTo: host.topAnchor, constant: 22),
                content.bottomAnchor.constraint(lessThanOrEqualTo: host.bottomAnchor, constant: -20)
            ])
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        aboutPanel = panel
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.alignment = .center
        label.isSelectable = true
        return label
    }

    @objc private func showLicenses() {
        if let licensePanel { licensePanel.makeKeyAndOrderFront(nil); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = L("开源许可")
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 280)
        let scroll = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.textContainerInset = NSSize(width: 22, height: 22)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.autoresizingMask = [.width]
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        let notices = ["LivePhotoStudio-MIT", "THIRD_PARTY_NOTICES", "Revive-MIT", "makelive-MIT"].compactMap { name -> String? in
            guard let url = Bundle.main.url(forResource: name, withExtension: "txt"), let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return name.replacingOccurrences(of: "-MIT", with: "") + "\n\n" + contents
        }
        let summary = L("采用 MIT 许可。部分代码基于 Revive，分享封装参考 makelive。第三方版权与许可随应用提供。")
        text.string = ([summary] + notices).joined(separator: "\n\n────────────────────────────────\n\n")
        scroll.documentView = text
        panel.contentView?.addSubview(scroll)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        licensePanel = panel
    }
}


struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Bindable private var preferences = AppPreferences.shared

    var body: some Commands {
        let _ = preferences.language
        let _ = AppMenuController.shared.setOpenWindowHandler { openWindow(id: "main") }
        CommandGroup(replacing: .appInfo) {
            Button(L("关于实况工坊")) { AppMenuController.shared.showAbout() }
        }
        CommandGroup(replacing: .appSettings) { }
        CommandGroup(replacing: .systemServices) { }
        CommandGroup(replacing: .appVisibility) { }
        CommandGroup(replacing: .help) { }
        CommandGroup(replacing: .newItem) { }
        CommandMenu(L("设置")) {
            Text(L("外观"))
            ForEach(AppAppearance.allCases, id: \.self) { appearance in
                Toggle(appearance.title, isOn: Binding(get: { preferences.appearance == appearance }, set: { if $0 { preferences.appearance = appearance } }))
            }
            Divider()
            Text(L("语言"))
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Toggle(language.title, isOn: Binding(get: { preferences.language == language }, set: { if $0 { preferences.language = language } }))
            }
            Divider()
            Button(L("存储与清理…")) {
                openWindow(id: "main")
                Model.shared.showFinished = false
                Task { @MainActor in
                    await Task.yield()
                    Model.shared.showFinishedSettings = true
                }
            }.disabled(Model.shared.busy)
            Button(UIStrings.isEnglish ? "Show Guide…" : "使用引导…") {
                openWindow(id: "main")
                Model.shared.startGuide()
            }.disabled(Model.shared.busy)
        }
    }
}
