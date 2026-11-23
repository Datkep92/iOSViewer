import Foundation
import UIKit
import UltraViewerProtocol

/// Builds the client registration request from real iOS device facts. It does
/// not invent Windows identity values: fields with no truthful iOS equivalent
/// are left empty, exactly as the desktop profile leaves them empty.
public enum IOSRegistrationProfile {
    public enum Error: Swift.Error, LocalizedError {
        case storageUnavailable
        case invalidStoredProfile
        case encodingFailed(String)

        public var errorDescription: String? {
            switch self {
            case .storageUnavailable: "Không truy cập được thư mục lưu cấu hình của ứng dụng."
            case .invalidStoredProfile: "Cấu hình đăng ký cũ không hợp lệ; đã tạo cấu hình mới."
            case let .encodingFailed(reason): "Không mã hóa được cấu hình đăng ký: \(reason)"
            }
        }
    }

    private struct Credentials {
        let deviceIdentity: String
        let password: String
    }

    private struct Environment {
        let hostName: String
        let userName: String
        let operatingSystem: OperatingSystemVersion
    }

    private static let maximumProfileBytes = 65_536
    public static let displayNameKey = "iOSViewer.displayName"
    public static let defaultDisplayName = "iOSViewer"

    /// Persisted credentials are generated on this device. No credential is
    /// present in the source tree or in the documentation.
    public static func loadOrCreate() throws -> ClientRegistration.Request {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else {
            throw Error.storageUnavailable
        }
        let directory = support.appendingPathComponent("iOSViewer", isDirectory: true)
            .appendingPathComponent("Client", isDirectory: true)
        let environment = Environment(hostName: UIDevice.current.name,
                                      userName: ProcessInfo.processInfo.environment["USER"] ?? "mobile",
                                      operatingSystem: ProcessInfo.processInfo.operatingSystemVersion)
        return try loadOrCreate(in: directory, environment: environment)
    }

    static func loadOrCreate(in directory: URL,
                             environment: Environment) throws -> ClientRegistration.Request {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        guard try manager.attributesOfItem(atPath: directory.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw Error.storageUnavailable
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let destination = directory.appendingPathComponent("registration.json", isDirectory: false)
        let credentials: Credentials
        if manager.fileExists(atPath: destination.path),
           let attributes = try? manager.attributesOfItem(atPath: destination.path),
           attributes[.type] as? FileAttributeType == .typeRegular,
           let size = attributes[.size] as? NSNumber,
           size.intValue > 0, size.intValue <= maximumProfileBytes,
           let stored = try? JSONDecoder().decode(ClientRegistration.Request.self,
                                                  from: Data(contentsOf: destination)),
           isValid(stored.deviceIdentity, password: stored.password) {
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            credentials = Credentials(deviceIdentity: stored.deviceIdentity, password: stored.password)
        } else {
            credentials = Credentials(deviceIdentity: randomIdentity(), password: randomPassword())
        }

        var request = makeRequest(credentials: credentials, environment: environment)
        do {
            _ = try request.encode()
            let bytes = try JSONEncoder().encode(request) + Data([10])
            try bytes.write(to: destination, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            throw Error.encodingFailed(error.localizedDescription)
        }
        return request
    }

    private static func isValid(_ identity: String, password: String) -> Bool {
        guard identity.utf8.count == 32,
              identity.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }),
              password.utf8.count == 8,
              password.utf8.allSatisfy({ (48...57).contains($0) }) else { return false }
        return true
    }

    private static func randomIdentity() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in
            String(format: "%02X", UInt8.random(in: 0...255, using: &generator))
        }.joined()
    }

    private static func randomPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<8).map { _ in String(UInt32.random(in: 0..<10, using: &generator)) }.joined()
    }

    private static func makeRequest(credentials: Credentials,
                                    environment: Environment) -> ClientRegistration.Request {
        .init(
            deviceIdentity: credentials.deviceIdentity,
            password: credentials.password,
            localAddress: try! RelayIPv4Address("0.0.0.0"),
            computerNameUTF8Base64: Data(environment.hostName.utf8).base64EncodedString(),
            clientVersion: "6.6.133",
            macAddress: "",
            diskIdentity: "",
            operatingSystem: operatingSystemWireValue(environment.operatingSystem),
            installerReferral: 0,
            customPassword: "",
            usesProxy: false,
            quickSupportMetadata: "",
            userNameWireValue: wireName(environment.userName),
            activeSessionID: 0,
            processSessionID: 0,
            preferredIDText: "0",
            referralIDText: "0",
            automaticUpdate: 0,
            systemFolderCreationTicks: "0",
            programFilesCreationTicks: "0",
            systemVolumeInformationCreationTicks: "0",
            licenseContext1: "",
            licenseContext2: "",
            captchaToken: ""
        )
    }

    /// .NET Version components: Build|Major|MajorRevision|Minor|MinorRevision|Revision.
    /// iOS has no product revision or patch sub-version, so those stay zero.
    public static func operatingSystemWireValue(
        _ version: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        "\(version.patchVersion)|\(version.majorVersion)|0|\(version.minorVersion)|0|0"
    }

    private static func wireName(_ value: String) -> String {
        value.utf8.allSatisfy { $0 < 128 } ? value : Data(value.utf8).base64EncodedString()
    }

    public static func loginDisplayName(defaults: UserDefaults = .standard) -> String {
        let reserved = Set("!#$&?:/\\*,.@<>;'\"=")
        let raw = (defaults.string(forKey: displayNameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folded = raw.folding(options: .diacriticInsensitive, locale: nil)
        let ascii = folded.filter {
            $0.isASCII && !reserved.contains($0) && $0.unicodeScalars.allSatisfy { (32...126).contains($0.value) }
        }
        let name = String(ascii.trimmingCharacters(in: .whitespaces).prefix(20))
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? defaultDisplayName : name
    }
}
