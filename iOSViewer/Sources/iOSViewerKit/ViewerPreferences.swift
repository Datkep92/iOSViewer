import Foundation

/// Cách iPhone dịch cử chỉ thành lệnh chuột trên máy Windows.
public enum RemotePointerMode: String, CaseIterable, Sendable {
    case absolute
    case trackpad
    case joystick

    public var title: String {
        switch self {
        case .absolute: return "Chạm trực tiếp"
        case .trackpad: return "Bàn rê"
        case .joystick: return "Cần điều khiển"
        }
    }
}

/// Một máy Windows đã kết nối, lưu lại để nối nhanh lần sau.
public struct SavedConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(partnerID)|\(password)" }
    public let partnerID: String
    public let password: String
    public let label: String
    public let lastUsed: Date

    public init(partnerID: String, password: String, label: String, lastUsed: Date = Date()) {
        self.partnerID = partnerID
        self.password = password
        self.label = label
        self.lastUsed = lastUsed
    }
}

/// Danh sách máy và tuỳ chọn phiên được giữ ngay trên thiết bị.
public enum ConnectionStore {
    private static let defaults = UserDefaults.standard
    private static let storageKey = "iOSViewer.savedConnections.v1"
    private static let maximumCount = 12

    public static func all() -> [SavedConnection] {
        guard let data = defaults.data(forKey: storageKey),
              let items = try? JSONDecoder().decode([SavedConnection].self, from: data) else { return [] }
        return items.sorted { $0.lastUsed > $1.lastUsed }
    }

    public static func save(partnerID: String, password: String, label: String? = nil) {
        let id = partnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !password.isEmpty else { return }
        var items = all().filter { $0.partnerID != id || $0.password != password }
        items.insert(SavedConnection(partnerID: id, password: password,
                                     label: label ?? "Máy \(id)"), at: 0)
        if items.count > maximumCount { items = Array(items.prefix(maximumCount)) }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func remove(partnerID: String, password: String) {
        let items = all().filter { $0.partnerID != partnerID || $0.password != password }
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}

public enum ViewerSettings {
    private static let defaults = UserDefaults.standard
    private static let modeKey = "iOSViewer.pointerMode.v1"
    private static let backgroundKey = "iOSViewer.keepConnectionInBackground.v1"

    public static var pointerMode: RemotePointerMode {
        get {
            guard let raw = defaults.string(forKey: modeKey),
                  let mode = RemotePointerMode(rawValue: raw) else { return .absolute }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: modeKey) }
    }

    /// Bật theo mặc định để đúng nhu cầu chuyển ứng dụng mà không mất kết nối.
    public static var keepConnectionInBackground: Bool {
        get {
            guard defaults.object(forKey: backgroundKey) != nil else { return true }
            return defaults.bool(forKey: backgroundKey)
        }
        set { defaults.set(newValue, forKey: backgroundKey) }
    }
}
