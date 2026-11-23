import CoreGraphics
import Foundation
import UIKit
import UltraViewerProtocol

/// Owns one relay/peer session and converts its events into UIKit-friendly
/// callbacks. All callbacks fire on the main actor.
@MainActor
public final class ViewerSessionController {
    public enum State: Sendable {
        case idle, connecting, connected
    }

    public var onStatus: ((String) -> Void)?
    public var onFrame: ((CGImage, CGSize) -> Void)?
    public var onState: ((State) -> Void)?
    public private(set) var state: State = .idle
    public private(set) var log: [String] = []

    /// Latest values received from the Windows host, exposed for the UI.
    public private(set) var lastChatText: String = ""
    public private(set) var lastClipboardText: String = ""
    public private(set) var pendingFileOfferID: String?
    public private(set) var pendingFileOfferName: String?

    public var hasPendingFileOffer: Bool {
        pendingFileOfferID != nil && pendingFileOfferName != nil
    }

    private var session: UltraViewerRelaySession?
    private var eventsTask: Task<Void, Never>?
    private var peer: UltraViewerRelaySession.Peer?
    private var inputAllowed = false
    private var warnedAboutInputPermission = false
    private var reportedFirstPointer = false
    private static let maximumLogLines = 200

    public init() {}

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
        let configuration = UltraViewerRelaySession.Configuration(
            registration: registration,
            listenerPort: 443,
            localScreenWidth: Int32(max(1, (bounds.width * scale).rounded())),
            localScreenHeight: Int32(max(1, (bounds.height * scale).rounded())),
            displayName: IOSRegistrationProfile.loginDisplayName(),
            captureDirectory: nil,
            // Avoids needing local-network permission on iOS; relay stays available.
            enableLANDirect: false
        )

        let session = UltraViewerRelaySession()
        let stream: AsyncThrowingStream<UltraViewerRelaySession.Event, any Swift.Error>
        do {
            stream = try await session.connect(configuration: configuration, partnerID: id, password: password)
        } catch {
            report("Không bắt đầu được phiên: \(error.localizedDescription)")
            return
        }

        self.session = session
        self.peer = nil
        self.inputAllowed = false
        self.warnedAboutInputPermission = false
        self.reportedFirstPointer = false
        self.lastChatText = ""
        self.lastClipboardText = ""
        self.pendingFileOfferID = nil
        self.pendingFileOfferName = nil
        self.state = .connecting
        self.onState?(state)
        report("Đang tìm \(id) qua dịch vụ UltraViewer…")

        eventsTask = Task { [weak self] in
            do {
                for try await event in stream {
                    await MainActor.run { self?.handle(event) }
                }
            } catch is CancellationError {
                // Expected when the user taps Ngắt.
            } catch {
                await MainActor.run { self?.finish(with: error.localizedDescription) }
            }
        }
    }

    public func disconnect() async {
        eventsTask?.cancel()
        eventsTask = nil
        let current = session
        session = nil
        await current?.close()
        inputAllowed = false
        warnedAboutInputPermission = false
        reportedFirstPointer = false
        lastChatText = ""
        lastClipboardText = ""
        pendingFileOfferID = nil
        pendingFileOfferName = nil
        peer = nil
        state = .idle
        onState?(state)
        report("Đã ngắt phiên.")
    }

    /// Coordinates are already in Windows desktop pixels; the view maps the
    /// touch point into that space before calling here.
    public func sendPointer(_ kind: RemotePointerKind, at point: CGPoint) {
        guard let session else { return }
        if !reportedFirstPointer {
            reportedFirstPointer = true
            report("Đã nhận cử chỉ, đang kiểm tra quyền điều khiển từ máy Windows.")
        }
        guard inputAllowed else {
            if !warnedAboutInputPermission {
                warnedAboutInputPermission = true
                report("Chưa có quyền điều khiển từ máy Windows. Hãy cho phép điều khiển trong UltraViewer bên Windows.")
            }
            return
        }
        let x = Int32(point.x.rounded())
        let y = Int32(point.y.rounded())
        let position = MouseMessage.packedPosition(x: Int16(clamping: x), y: Int16(clamping: y))
        let messages: [MouseMessage]
        switch kind {
        case .move:
            messages = [.move(wParam: 0, x: x, y: y)]
        case .leftClick:
            messages = [.move(wParam: 0, x: x, y: y),
                        .button(.leftDown, wParam: 1, lParam: position),
                        .button(.leftUp, wParam: 0, lParam: position)]
        case .doubleClick:
            messages = [.move(wParam: 0, x: x, y: y),
                        .button(.leftDoubleClick, wParam: 1, lParam: position)]
        case .rightClick:
            messages = [.move(wParam: 0, x: x, y: y),
                        .button(.rightDown, wParam: 2, lParam: position),
                        .button(.rightUp, wParam: 0, lParam: position)]
        case let .wheel(delta):
            messages = [.verticalWheel(wParam: MouseMessage.wheelWParam(delta: delta, keyFlags: 0),
                                       lParam: position)]
        case let .horizontalWheel(delta):
            messages = [.horizontalWheel(wParam: MouseMessage.wheelWParam(delta: delta, keyFlags: 0),
                                         lParam: position)]
        }
        Task { [weak self] in
            for message in messages {
                do {
                    try await session.send(message.encode())
                } catch {
                    await MainActor.run {
                        self?.report("Không gửi được lệnh chuột: \(error.localizedDescription)")
                    }
                    return
                }
            }
        }
    }

    // MARK: - Session tools

    public func sendChat(_ text: String) async {
        guard let session else {
            report("Chưa có phiên kết nối để gửi tin nhắn.")
            return
        }
        guard !text.isEmpty else {
            report("Nhập nội dung tin nhắn trước khi gửi.")
            return
        }
        do {
            try await session.sendChat(text)
            report("Đã gửi tin nhắn.")
        } catch {
            report("Không gửi được tin nhắn: \(error.localizedDescription)")
        }
    }

    public func sendClipboardText(_ text: String) async {
        guard let session else {
            report("Chưa có phiên kết nối để gửi bảng nhớ tạm.")
            return
        }
        do {
            try await session.setClipboardSharing(true)
            try await session.sendClipboard(text)
            report("Đã gửi bảng nhớ tạm (\(text.utf8.count) byte).")
        } catch {
            report("Không gửi được bảng nhớ tạm: \(error.localizedDescription)")
        }
    }

    public func sendKeyboardText(_ text: String) async {
        guard let session else {
            report("Chưa có phiên kết nối để gửi bàn phím.")
            return
        }
        guard !text.isEmpty else {
            report("Không có nội dung để gửi qua bàn phím.")
            return
        }
        for unit in text.utf16 {
            let keyDown = KeyboardMessage(kind: .keyDown, virtualKey: 0, scanCode: 0,
                                          character: unit, capsLockOn: false)
            let keyUp = KeyboardMessage(kind: .keyUp, virtualKey: 0, scanCode: 0,
                                        character: unit, capsLockOn: false)
            do {
                try await session.send(keyDown.encode())
                try await session.send(keyUp.encode())
            } catch {
                report("Không gửi được bàn phím: \(error.localizedDescription)")
                return
            }
        }
        report("Đã gửi bàn phím (chưa kiểm chứng trên Windows).")
    }

    public func sendFile(at url: URL) async {
        guard let session else {
            report("Chưa có phiên kết nối để gửi tệp.")
            return
        }
        do {
            let offer = try await session.sendFile(url)
            report("Đã gửi tệp \(offer.fileName) (mã \(offer.transferID)).")
        } catch {
            report("Không gửi được tệp \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    public func acceptLastFileOffer(to directory: URL) async {
        guard let session else {
            report("Chưa có phiên kết nối để nhận tệp.")
            return
        }
        guard let id = pendingFileOfferID, let name = pendingFileOfferName else {
            report("Chưa có đề nghị gửi tệp nào để nhận.")
            return
        }
        let destination = Self.safeDestination(for: name, in: directory)
        do {
            try await session.acceptFile(id, to: destination)
            pendingFileOfferID = nil
            pendingFileOfferName = nil
            report("Đang nhận \(destination.lastPathComponent) (mã \(id)).")
        } catch {
            report("Không nhận được tệp \(name): \(error.localizedDescription)")
        }
    }

    public func setComputerAudioEnabled(_ enabled: Bool) async {
        guard let session else {
            report("Chưa có phiên kết nối để đổi âm thanh máy tính.")
            return
        }
        do {
            try await session.setComputerAudioEnabled(enabled)
            report(enabled
                ? "Đã gửi yêu cầu bật âm thanh máy tính (bản iOS chưa phát âm thanh)."
                : "Đã gửi yêu cầu tắt âm thanh máy tính.")
        } catch {
            report("Không đổi được âm thanh máy tính: \(error.localizedDescription)")
        }
    }

    public func setCursorPositionsEnabled(_ enabled: Bool) async {
        guard let session else {
            report("Chưa có phiên kết nối để đổi vị trí con trỏ.")
            return
        }
        do {
            try await session.sendCommand(RemoteControlCommands.cursorPositions(enabled: enabled),
                                          requiresControl: false)
            report(enabled ? "Đã bật gửi vị trí con trỏ." : "Đã tắt gửi vị trí con trỏ.")
        } catch {
            report("Không đổi được vị trí con trỏ: \(error.localizedDescription)")
        }
    }

    public func setQuality(_ preset: RemoteControlCommands.QualityPreset) async {
        guard let session else {
            report("Chưa có phiên kết nối để đổi chất lượng.")
            return
        }
        do {
            for message in RemoteControlCommands.qualityPreset(preset) {
                try await session.sendCommand(message, requiresControl: false)
            }
            report("Đã gửi thiết lập chất lượng: \(Self.qualityLabel(preset)).")
        } catch {
            report("Không đổi được chất lượng: \(error.localizedDescription)")
        }
    }

    public func setWallpaperVisible(_ visible: Bool) async {
        guard let session else {
            report("Chưa có phiên kết nối để đổi hình nền.")
            return
        }
        do {
            try await session.sendCommand(RemoteControlCommands.wallpaper(visible: visible),
                                          requiresControl: false)
            report(visible ? "Đã gửi yêu cầu hiện hình nền." : "Đã gửi yêu cầu ẩn hình nền.")
        } catch {
            report("Không đổi được hình nền: \(error.localizedDescription)")
        }
    }

    public func sendAction(_ action: RemoteControlCommands.Action) async {
        guard let session else {
            report("Chưa có phiên kết nối để gửi lệnh.")
            return
        }
        // Same one-shot permission warning as sendPointer.
        guard inputAllowed else {
            if !warnedAboutInputPermission {
                warnedAboutInputPermission = true
                report("Chưa có quyền điều khiển từ máy Windows. Hãy cho phép điều khiển trong UltraViewer bên Windows.")
            }
            return
        }
        do {
            try await session.sendCommand(RemoteControlCommands.action(action), requiresControl: true)
            report("Đã gửi lệnh \(String(describing: action)) (chưa kiểm chứng trên Windows).")
        } catch {
            report("Không gửi được lệnh \(String(describing: action)): \(error.localizedDescription)")
        }
    }

    public func requestSideSwitch(ownID: String, password: String) async {
        guard let session else {
            report("Chưa có phiên kết nối để đổi chiều điều khiển.")
            return
        }
        let message: RemoteControlCommands.Message
        do {
            message = try RemoteControlCommands.sideSwitch(ownID: ownID, password: password)
        } catch {
            report("Không gửi được yêu cầu đổi chiều: \(error.localizedDescription)")
            return
        }
        // The UI must call this only after the user explicitly confirmed.
        report("Đang gửi ID và mật khẩu phiên của mình sang máy Windows để đổi chiều điều khiển.")
        do {
            try await session.sendCommand(message, requiresControl: false)
            report("Đã gửi thông tin đăng nhập của mình sang máy Windows (chỉ thực hiện sau khi bạn xác nhận).")
        } catch {
            report("Không gửi được yêu cầu đổi chiều: \(error.localizedDescription)")
        }
    }

    private static func qualityLabel(_ preset: RemoteControlCommands.QualityPreset) -> String {
        switch preset {
        case .automatic: return "tự động"
        case .speed: return "ưu tiên tốc độ"
        case .quality: return "ưu tiên chất lượng"
        @unknown default: return String(describing: preset)
        }
    }

    private static func clipboardSummary(_ text: String) -> String {
        let sanitized = String(text.unicodeScalars.map { scalar -> Character in
            let category = scalar.properties.generalCategory
            return category == .control || category == .format ? " " : Character(scalar)
        })
        let prefix = String(sanitized.prefix(120))
        return sanitized.count > 120 ? prefix + "…" : prefix
    }

    private static func safeDestination(for name: String, in directory: URL) -> URL {
        let components = name.components(separatedBy: CharacterSet(charactersIn: "/\\"))
        let base = components.last(where: { !$0.isEmpty && $0 != "." && $0 != ".." }) ?? "received-file"
        let fileManager = FileManager.default
        let nsBase = base as NSString
        let stem = nsBase.deletingPathExtension
        let ext = nsBase.pathExtension
        var candidate = directory.appendingPathComponent(base)
        var index = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? " (\(index))" : " (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(stem + suffix)
            index += 1
        }
        return candidate
    }

    private func applyInputPermission(_ allowed: Bool) {
        guard inputAllowed != allowed else { return }
        inputAllowed = allowed
        if allowed { warnedAboutInputPermission = false }
        report(allowed ? "Điều khiển từ xa đã được cho phép." : "Chỉ xem; điều khiển từ xa tạm dừng.")
    }

    private func handle(_ event: UltraViewerRelaySession.Event) {
        switch event {
        case let .status(text):
            report(text)
        case let .accepted(newPeer):
            peer = newPeer
            state = .connected
            onState?(state)
            // A host can send its view-only byte before the session becomes
            // active, in which case no separate inputPermission event follows.
            applyInputPermission(newPeer.allowsRemoteInput)
            report("Đã kết nối \(newPeer.width)×\(newPeer.height).")
        case let .screenChanged(newPeer):
            peer = newPeer
            applyInputPermission(newPeer.allowsRemoteInput)
            report("Màn hình máy Windows đổi kích thước: \(newPeer.width)×\(newPeer.height).")
        case let .frame(latest):
            guard let bitmap = latest.take(), let image = bitmap.makeCGImage() else { return }
            let size = peer.map { CGSize(width: $0.width, height: $0.height) }
                ?? CGSize(width: bitmap.width, height: bitmap.height)
            onFrame?(image, size)
        case let .inputPermission(allowed):
            applyInputPermission(allowed)
        case let .chat(text):
            lastChatText = text
            report("Tin nhắn: \(text)")
        case let .typing(typing):
            if typing { report("Bên kia đang gõ…") }
        case let .clipboard(text):
            lastClipboardText = text
            report("Bảng nhớ tạm (\(text.utf8.count) byte): \(Self.clipboardSummary(text))")
        case .computerAudio:
            report("Nhận âm thanh máy tính — bản iOS chưa phát âm thanh.")
        case let .cursor(cursor):
            if case let .position(x, y) = cursor {
                report("Con trỏ từ xa: \(x),\(y) — chưa vẽ lớp phủ.")
            } else {
                report("Nhận trạng thái con trỏ từ xa — chưa vẽ lớp phủ.")
            }
        case let .latency(milliseconds):
            report("Độ trễ: \(Int(milliseconds)) ms.")
        case .sideSwitchRequested:
            report("Máy Windows yêu cầu đổi chiều điều khiển — chưa hỗ trợ.")
        case let .fileOffer(offer):
            pendingFileOfferID = offer.transferID
            pendingFileOfferName = offer.fileName
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

    private func finish(with reason: String) {
        eventsTask = nil
        session = nil
        inputAllowed = false
        warnedAboutInputPermission = false
        reportedFirstPointer = false
        lastChatText = ""
        lastClipboardText = ""
        pendingFileOfferID = nil
        pendingFileOfferName = nil
        peer = nil
        state = .idle
        onState?(state)
        report("Phiên kết thúc: \(reason)")
    }

    private func report(_ text: String) {
        let line = text.isEmpty ? " " : text
        log.append(line)
        if log.count > Self.maximumLogLines { log.removeFirst(log.count - Self.maximumLogLines) }
        onStatus?(line)
    }
}
