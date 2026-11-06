import Cocoa
import OSLog
import FinderSync
import UniformTypeIdentifiers
@objc(LivePhotoFinder) final class LivePhotoFinder: FIFinderSync {
 override init() {
 super.init()
 FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/Users"), URL(fileURLWithPath: "/Volumes")]
 }
 override func menu(for menuKind: FIMenuKind) -> NSMenu? {
 guard menuKind == .contextualMenuForItems,
 let urls = FIFinderSyncController.default().selectedItemURLs(), urls.count == 1,
 let url = urls.first, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) else { return nil }
 let menu = NSMenu()
 let item = NSMenuItem(title: NSLocalizedString("Convert to Live Photo", comment: "Finder contextual action"), action: #selector(convert(_:)), keyEquivalent: "")
 item.target = self; item.representedObject = url
 item.image = NSImage(systemSymbolName:"livephoto", accessibilityDescription:nil)
 menu.addItem(item); return menu
 }
 @objc func convert(_ sender: NSMenuItem) {
 Logger().notice("LP ACTION invoked")
 guard let url = FIFinderSyncController.default().selectedItemURLs()?.first else { Logger().error("LP no selected URL"); return }
 var target = URLComponents()
 target.scheme = Bundle.main.bundleIdentifier == "local.livephotostudio.test.finder" ? "livephotostudio-test" : "livephotostudio"; target.host = "open"
 target.queryItems = [URLQueryItem(name:"path",value:url.path)]
 if let link = target.url { let opened = NSWorkspace.shared.open(link); Logger().notice("LP open accepted=\(opened)") }
 }
}
