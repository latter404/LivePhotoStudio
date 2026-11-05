import AppKit
import UniformTypeIdentifiers

/// Present outside the SwiftUI button callback, without a nested modal run loop.
@MainActor enum FilePanels {
 static func confirmAirDropCleanup() async -> Bool {
 await Task.yield()
 let alert=NSAlert()
 alert.messageText=L("已确认接收成功？")
 alert.informativeText=L("macOS 不会可靠地区分投送完成与取消。确认接收设备已收到后，再将本次处理结果移到废纸篓。")
 alert.addButton(withTitle:L("保留结果"))
 alert.addButton(withTitle:L("移到废纸篓"))
 alert.buttons[0].keyEquivalent="\r"
 alert.buttons[1].keyEquivalent=""
 guard let window=NSApp.keyWindow ?? NSApp.mainWindow else { return false }
 return await withCheckedContinuation { continuation in
 alert.beginSheetModal(for:window) { response in
 continuation.resume(returning:response == .alertSecondButtonReturn)
 }
 }
 }
 static func selectVideo() async -> URL? {
 ExportDiagnostics.record("open.panel.create")
 let panel=NSOpenPanel();panel.allowedContentTypes=[.movie]
 panel.allowsMultipleSelection=false;panel.canChooseDirectories=false
 return await present(panel,operation:"open")
 }
 static func selectExportDirectory() async -> URL? {
 ExportDiagnostics.record("live.panel.create")
 let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true
 panel.allowsMultipleSelection=false;panel.canCreateDirectories=true;panel.prompt=L("导出到这里")
 return await present(panel,operation:"live")
 }
 static func selectGIFDestination(name:String) async -> URL? {
 ExportDiagnostics.record("gif.panel.create")
 let panel=NSSavePanel();panel.allowedContentTypes=[.gif];panel.nameFieldStringValue=name
 return await present(panel,operation:"gif")
 }
 static func selectFinishedDirectory(current:URL) async -> URL? {
 let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true
 panel.allowsMultipleSelection=false;panel.canCreateDirectories=true
 panel.directoryURL=current.deletingLastPathComponent().deletingLastPathComponent();panel.prompt=L("选择位置")
 return await present(panel,operation:"finished.location")
 }
 private static func present(_ panel:NSSavePanel,operation:String) async -> URL? {
 await Task.yield()
 let window=NSApp.windows.first(where:{$0.identifier?.rawValue == "main" && $0.isVisible}) ?? NSApp.mainWindow
 ExportDiagnostics.record(operation+".panel.configured")
 return await withCheckedContinuation { continuation in
 let completion:(NSApplication.ModalResponse)->Void = { response in
 ExportDiagnostics.record(operation+(response == .OK ? ".panel.accepted" : ".panel.cancelled"))
 continuation.resume(returning:response == .OK ? panel.url : nil)
 }
 if let window,window.attachedSheet == nil {
 ExportDiagnostics.record(operation+".panel.sheet")
 panel.beginSheetModal(for:window,completionHandler:completion)
 } else {
 ExportDiagnostics.record(operation+".panel.standalone")
 panel.begin(completionHandler:completion)
 }
 }
 }
}
