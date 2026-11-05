import SwiftUI

struct FinishedSettingsView: View {
    @Bindable private var preferences = FinishedPreferences.shared
    @Bindable var model: Model
    @Environment(\.dismiss) private var dismiss
    @State private var showsLocationStatus = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label(L("存储与清理"), systemImage: "tray.full").font(.title2.weight(.semibold))
                Spacer()
                Button(L("完成")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text(L("自动删除处理结果")).font(.headline)
                Toggle(isOn: $preferences.deleteAfterPhotos) {
                    Label(L("添加到照片后"), systemImage: "photo.on.rectangle")
                }.help(L("成功添加到照片后，将所选处理结果移到废纸篓。"))
                Toggle(isOn: $preferences.deleteAfterAirDrop) {
                    Label(L("隔空投送后"), systemImage: "antenna.radiowaves.left.and.right")
                }.help(L("投送窗口关闭后，确认接收成功再清理处理结果。"))
                if preferences.deleteAfterAirDrop {
                    Text(L("投送窗口关闭后，确认接收成功再清理处理结果。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(isOn: $preferences.deleteAfterExport) {
                    Label(L("导出文件后"), systemImage: "folder")
                }.help(L("成功导出文件后，将所选处理结果移到废纸篓。"))
                Text(L("只清理应用内处理结果，不影响原视频、照片图库或导出的文件。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.switch).tint(.accentColor)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L("保存位置"), systemImage: "externaldrive").font(.headline)
                    Spacer()
                    Button(L("更改…")) {
                        model.finishedStatus = ""; showsLocationStatus = true
                        model.chooseFinishedLocation()
                    }.disabled(model.busy)
                }
                Text(preferences.directoryPath)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    .help(preferences.directoryPath).textSelection(.enabled)
            }
            if showsLocationStatus && !model.finishedStatus.isEmpty {
                HStack(spacing:8) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(L(model.finishedStatus)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(model.busy)
    }
}
