import CryptoKit
import Foundation

/// The trained Zstandard dictionary used by the recovered desktop decoder.
/// This iOS port never embeds it. The user supplies a lawfully obtained copy
/// through the Files picker, or places it in the app's Documents directory.
public enum UltraViewerScreenDictionary {
    public enum Error: Swift.Error, LocalizedError {
        case notProvided
        case invalidFile(String)

        public var errorDescription: String? {
            switch self {
            case .notProvided: "Chưa có tệp 8bit.dat. Hãy chọn tệp từ bản UltraViewer hợp pháp của bạn."
            case let .invalidFile(reason): "Tệp 8bit.dat không hợp lệ: \(reason)"
            }
        }
    }

    public static let fileName = "8bit.dat"
    public static let expectedByteCount = 112_640
    public static let expectedSHA256 = "9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b"

    private static let lock = NSLock()
    private static var selectedURL: URL?

    /// Default location: this app's sandbox Documents/8bit.dat.
    public static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Points the decoder at a user-chosen file. Nothing is copied by this call.
    public static func use(_ url: URL) {
        lock.lock()
        selectedURL = url
        lock.unlock()
    }

    public static func load() throws -> Data {
        lock.lock()
        let url = selectedURL ?? defaultFileURL()
        lock.unlock()

        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            throw Error.notProvided
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Error.invalidFile("không đọc được (\(error.localizedDescription))")
        }
        guard data.count == expectedByteCount else {
            throw Error.invalidFile("kích thước \(data.count), cần \(expectedByteCount) byte")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256 else {
            throw Error.invalidFile("mã băm không khớp")
        }
        return data
    }
}
