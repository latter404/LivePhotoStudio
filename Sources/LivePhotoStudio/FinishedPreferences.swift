import Foundation
import Observation

@MainActor @Observable final class FinishedPreferences {
    static let shared = FinishedPreferences()
    @ObservationIgnored private let defaults: UserDefaults

    var deleteAfterPhotos: Bool {
        didSet { defaults.set(deleteAfterPhotos, forKey: "finished.deleteAfterPhotos") }
    }
    var deleteAfterAirDrop: Bool {
        didSet { defaults.set(deleteAfterAirDrop, forKey: "finished.deleteAfterAirDrop") }
    }
    var deleteAfterExport: Bool {
        didSet { defaults.set(deleteAfterExport, forKey: "finished.deleteAfterExport") }
    }
    private(set) var directoryPath: String
    var directoryURL: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        deleteAfterPhotos = defaults.bool(forKey: "finished.deleteAfterPhotos")
        deleteAfterAirDrop = defaults.bool(forKey: "finished.deleteAfterAirDrop")
        deleteAfterExport = defaults.bool(forKey: "finished.deleteAfterExport")
        if let path = defaults.string(forKey: "finished.directoryPath"), path.hasPrefix("/") {
            directoryPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        } else {
            directoryPath = FinishedStore.defaultRoot.path
        }
    }

    func setDirectory(_ url: URL) {
        guard url.isFileURL else { return }
        directoryPath = url.standardizedFileURL.path
        defaults.set(directoryPath, forKey: "finished.directoryPath")
    }
}
