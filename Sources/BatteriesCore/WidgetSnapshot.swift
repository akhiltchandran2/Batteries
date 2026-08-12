import Foundation

/// Snapshot written by the main app after each refresh and read by the
/// widget extension. A WidgetKit extension can't run system_profiler or
/// libimobiledevice itself, so this file is the only channel between the
/// two processes. Deliberately Foundation-only so it compiles into the
/// plain SwiftPM executable, the Xcode app target, and the widget
/// extension target without pulling in AppKit or WidgetKit.
struct WidgetSnapshot: Codable {
    struct Entry: Codable, Identifiable {
        var id: String
        var name: String
        var symbolName: String
        var percent: Int?
        var isCharging: Bool
    }

    var mac: Entry?
    var devices: [Entry]
    var generatedAt: Date

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PowerDeck", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("widget-snapshot.json")
    }

    func write() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
