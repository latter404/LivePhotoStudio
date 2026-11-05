import Foundation
struct Localizer {
 static let shared = Localizer()
 func t(_ key: String, _ args: String...) -> String {
 let labels = ["err_no_video":"文件中没有视频轨道", "err_read":"读取失败", "err_write":"导出失败", "err_still":"封面生成失败", "err_cancelled":"已取消"]
 return L(labels[key] ?? key) + (args.isEmpty ? "" : ": " + args.map { L($0) }.joined(separator: " / "))
 }
}
