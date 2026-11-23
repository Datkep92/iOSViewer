import CoreGraphics
import Foundation
import RemoteControlKit
import UIKit
import UltraViewerProtocol

/// Owns one reusable remote-control client and converts its events into
/// UIKit-friendly callbacks. All callbacks fire on the main actor.
@MainActor
public final class ViewerSessionController {
    public typealias State = RemoteControlClient.State

    public var onStatus: ((String) -> Void)?
    public var onFrame: ((CGImage, CGSize) -> Void)?
    public var onState: ((State) -> Void)?
    public var onPermission: ((Bool) -> Void)?

    public var state: State { client.state }
    public var allowsRemoteInput: Bool { client.allowsRemoteInput }
    public private(set) var log: [String] = []

    /// Latest values received from the Windows host, exposed for the UI.
    public private(set) var lastChatText: String = ""
    public private(set) var lastClipboardText: String = ""
    public var pendingFileOfferID: String? { client.pendingFileOfferID }
    public var pendingFileOfferName: String? { client.pendingFileOfferName }

    public var hasPendingFileOffer: Bool { client.hasPendingFileOffer }

    private let client = RemoteControlClient()
    private static let maximumLogLines = 200

    public init() {
        client.onLog = { [weak self] text in self?.report(text) }
        client.onState = { [weak self] state in self?.onState?(state) }
        client.onPermission = { [weak self] allowed in self?.applyInputPermission(allowed) }
        client.onEvent = { [weak self] event in self?.handle(event) }
    }

    public func connect(partnerID: String, password: String) async {
        guard state == .idle else { return }
        let id = partnerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), !password.isEmpty else {
            report("Nhập ID máy Windows (chỉ chữ số) và mật khẩu phiên.")
            return
        }
        do {
            _ = try UltraViewerScreenDictionary.load()
        } catch {
            report("Chưa thể kết nối: \(error.localizedDescription)")
            return
        }
        let registration: ClientRegistration.Request
        do {
            registration = try IOSRegistrationProfile.loadOrCreate()
        } catch {
            report("Chưa thể đọc cấu hình đăng ký: \(error.localizedDescription)")
            return
        }

        let screen = UIScreen.main
        let scale = screen.scale
        let bounds = screen.bounds
        let configuration = RemoteControlClient.Configuration(
            registration: registration,
            listenerPort: 443,
            localScreenWidth: Int32(max(1, (bounds.width * scale).rounded())),
            localScreenHeight: Int32(max(1, (bounds.height * scale).rounded())),
            displayName: IOSRegistrationProfile.loginDisplayName(),
            captureDirectory: nil,
            // Avoids needing local-network permission on iOS; relay stays available.
            enableLANDirect: false,
            partnerID: id,
            password: password
        )

        lastChatText = ""
        lastClipboardText = ""
        await client.connect(configuration: configuration, autoReconnect: true)
    }

    public func disconnect() async {
        await client.disconnect()
        lastChatText = ""
        lastClipboardText = ""
        report("Đã ngắt phiên.")
    }

    /// Reuses the last credentials after a drop or on the user's request.
    public func reconnect() async {
        await client.reconnect()
    }

    // MARK: - Input

    /// Coordinates are already in Windows desktop pixels; the view maps the
    /// touch point into that space before calling here.
    public func sendPointer(_ kind: RemotePointerKind, at point: CGPoint) {
        client.sendPointer(kind, at: point)
    }

    // MARK: - Session tools

    public func sendChat(_ text: String) async { await client.sendChat(text) }

    public func sendClipboardText(_ text: String) async { await client.sendClipboardText(text) }

    public func sendKeyboardText(_ text: String) async { await client.sendKeyboardText(text) }

    public func sendFile(at url: URL) async { await client.sendFile(at: url) }

    public func acceptLastFileOffer(to directory: URL) async {
        await client.acceptLastFileOffer(to: directory)
    }

    public func setComputerAudioEnabled(_ enabled: Bool) async {
        await client.setComputerAudioEnabled(enabled)
    }

    public func setCursorPositionsEnabled(_ enabled: Bool) async {
        await client.setCursorPositionsEnabled(enabled)
    }

    public func setQuality(_ preset: RemoteControlCommands.QualityPreset) async {
        await client.setQuality(preset)
    }

    public func setWallpaperVisible(_ visible: Bool) async {
        await client.setWallpaperVisible(visible)
    }

    public func sendAction(_ action: RemoteControlCommands.Action) async {
        await client.sendAction(action)
    }

    /// Re-asks the Windows host for interactive control without dropping the session.
    public func requestControlPermission() async {
        await client.requestControlPermission()
    }

    public func requestSideSwitch(ownID: String, password: String) async {
        await client.requestSideSwitch(ownID: ownID, password: password)
    }

    // MARK: - Events

    private func applyInputPermission(_ allowed: Bool) {
        onPermission?(allowed)
    }

    private func handle(_ event: UltraViewerRelaySession.Event) {
        switch event {
        case .status(_):
            // The client already forwarded this to onStatus.
            break
        case let .accepted(peer):
            lastChatText = ""
            lastClipboardText = ""
            report("Đã kết nối \(peer.width)×\(peer.height).")
        case let .screenChanged(peer):
            report("Màn hình máy Windows đổi kích thước: \(peer.width)×\(peer.height).")
        case let .frame(latest):
            guard let bitmap = latest.take(), let image = bitmap.makeCGImage() else { return }
            let size = client.screenSize.width > 0
                ? client.screenSize
                : CGSize(width: bitmap.width, height: bitmap.height)
            onFrame?(image, size)
        case .inputPermission(_):
            // The client logs the change and drives onPermission.
            break
        case let .chat(text):
            lastChatText = text
            report("Tin nhắn: \(text)")
        case let .typing(typing):
            if typing { report("Bên kia đang gõ…") }
        case let .clipboard(text):
            lastClipboardText = text
            report("Bảng nhớ tạm (\(text.utf8.count) byte): \(Self.clipboardSummary(text))")
        case .computerAudio(_):
            report("Nhận âm thanh máy tính — bản iOS chưa phát âm thanh.")
        case let .cursor(cursor):
            if case let .position(x, y) = cursor {
                report("Con trỏ từ xa: \(x),\(y) — chưa vẽ lớp phủ.")
            } else {
                report("Nhận trạng thái con trỏ từ xa — chưa vẽ lớp phủ.")
            }
        case let .latency(milliseconds):
            report("Độ trễ: \(Int(milliseconds)) ms.")
        case .sideSwitchRequested(_):
            report("Máy Windows yêu cầu đổi chiều điều khiển — chưa hỗ trợ.")
        case let .fileOffer(offer):
            report("Nhận đề nghị gửi tệp \(offer.fileName) (\(offer.size) byte) — chọn «Nhận tệp» để lưu.")
        case let .fileProgress(transferID, bytes):
            report("Truyền \(transferID): \(bytes) byte.")
        case let .fileCompleted(transferID):
            report("Đã xong \(transferID).")
        case let .fileCanceled(transferID):
            report("Đã hủy \(transferID).")
        case let .fileFailed(transferID, reason):
            report("Lỗi \(transferID): \(reason)")
        }
    }

    private func report(_ text: String) {
        let line = text.isEmpty ? " " : text
        log.append(line)
        if log.count > Self.maximumLogLines { log.removeFirst(log.count - Self.maximumLogLines) }
        onStatus?(line)
    }

    private static func clipboardSummary(_ text: String) -> String {
        let sanitized = String(text.unicodeScalars.map { scalar -> Character in
            let category = scalar.properties.generalCategory
            return category == .control || category == .format ? " " : Character(scalar)
        })
        let prefix = String(sanitized.prefix(120))
        return sanitized.count > 120 ? prefix + "…" : prefix
    }
}
