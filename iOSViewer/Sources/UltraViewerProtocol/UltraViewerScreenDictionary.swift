import CryptoKit
import Foundation

/// The trained Zstandard dictionary used by the recovered desktop decoder.
/// Clean builds never embed it; private device builds may ship a lawful copy.
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

    private static func bundledFileURL() -> URL? {
        Bundle.main.url(forResource: "8bit", withExtension: "dat")
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validatedData(at url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Error.notProvided }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw Error.invalidFile("không đọc được (\(error.localizedDescription))")
        }
        guard data.count == expectedByteCount else {
            throw Error.invalidFile("kích thước \(data.count), cần \(expectedByteCount) byte")
        }
        guard digest(data) == expectedSHA256 else {
            throw Error.invalidFile("mã băm không khớp")
        }
        return data
    }

    /// Points the decoder at a user-chosen file. Nothing is copied by this call.
    public static func use(_ url: URL) {
        lock.lock()
        selectedURL = url
        lock.unlock()
    }

    /// Copies a dictionary shipped inside this app bundle into Documents.
    /// Public builds have no bundled copy, so this is a no-op for them.
    /// A corrupt file left by an earlier import is replaced with the valid copy.
    public static func installBundledDictionaryIfNeeded() {
        guard let bundled = bundledFileURL() else {
            NSLog("iOSViewer: no bundled dictionary")
            return
        }
        guard let destination = defaultFileURL() else {
            NSLog("iOSViewer: no Documents directory")
            return
        }
        do {
            let data = try validatedData(at: bundled)
            if FileManager.default.fileExists(atPath: destination.path) {
                if let existing = try? validatedData(at: destination) {
                    use(destination)
                    NSLog("iOSViewer: existing dictionary is valid")
                    return
                }
                NSLog("iOSViewer: replacing invalid dictionary in Documents")
            }
            try data.write(to: destination, options: .atomic)
            use(destination)
            NSLog("iOSViewer: installed bundled dictionary (\(data.count) bytes)")
        } catch {
            NSLog("iOSViewer: could not install bundled dictionary: \(error.localizedDescription)")
        }
    }

    /// Loads the first valid copy: chosen file, Documents, then the bundled copy.
    public static func load() throws -> Data {
        lock.lock()
        let selected = selectedURL
        lock.unlock()

        var lastError: Swift.Error?
        if let selected {
            do {
                return try validatedData(at: selected)
            } catch {
                lastError = error
            }
        }
        if let documents = defaultFileURL() {
            do {
                let data = try validatedData(at: documents)
                use(documents)
                return data
            } catch {
                lastError = error
            }
        }
        if let bundled = bundledFileURL() {
            do {
                let data = try validatedData(at: bundled)
                use(bundled)
                NSLog("iOSViewer: using bundled dictionary (\(data.count) bytes)")
                return data
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Error.notProvided
    }
}
