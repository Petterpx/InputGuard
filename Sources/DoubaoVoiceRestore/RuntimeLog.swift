import Foundation

final class RuntimeLog {
    static let shared = RuntimeLog()

    let fileURL: URL
    private let queue = DispatchQueue(label: "dev.petterp.DoubaoVoiceRestore.log")
    private let formatter: DateFormatter

    private init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DoubaoVoiceRestore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("runtime.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
    }

    func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL)
            }
        }
    }

    /// 等待队列里已排入的写入落盘。进程退出前调用，避免最后一行日志丢失。
    func flush() {
        queue.sync {}
    }
}
