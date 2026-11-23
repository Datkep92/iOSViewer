import CoreGraphics
import Foundation
import UltraViewerProtocol

/// Touch gestures translated into Windows mouse events. This lives beside the
/// transport so any SwiftUI/UIKit client can reuse the same command encoding.
public enum RemotePointerKind: Sendable {
    case move, leftClick, doubleClick, rightClick
    /// One Windows wheel notch is a signed multiple of 120 in the high word.
    case wheel(delta: Int16)
    case horizontalWheel(delta: Int16)
}

/// Reusable engine for one UltraViewer session: relay connection, automatic
/// retry, control-permission requests and batched input commands. It knows
/// nothing about UIKit, so a different screen can embed it as a package.
@MainActor
public final class RemoteControlClient {
    public enum State: Sendable, Equatable {
        case idle, connecting, connected
    }

    public struct Configuration: Sendable {
        public var registration: ClientRegistration.Request
        public var commandHost: String
        public var listenerPort: UInt16
        public var localScreenWidth: Int32
        public var localScreenHeight: Int32
        public var displayName: String
        public var captureDirectory: URL?
        public var enableLANDirect: Bool
        public var partnerID: String
        public var password: String

        public init(registration: ClientRegistration.Request,
                    commandHost: String = "functions3.ultraviewer.net",
                    listenerPort: UInt16 = 443,
                    localScreenWidth: Int32,
                    localScreenHeight: Int32,
                    displayName: String,
                    captureDirectory: URL? = nil,
                    enableLANDirect: Bool = false,
                    partnerID: String,
                    password: String) {
            self.registration = registration
            self.commandHost = commandHost
            self.listenerPort = listenerPort
            self.localScreenWidth = localScreenWidth
            self.localScreenHeight = localScreenHeight
            self.displayName = displayName
            self.captureDirectory = captureDirectory
            self.enableLANDirect = enableLANDirect
            self.partnerID = partnerID
            self.password = password
        }
    }

    public var onEvent: ((UltraViewerRelaySession.Event) -> Void)?
    public var onState: ((State) -> Void)?
    public var onPermission: ((Bool) -> Void)?
    public var onLog: ((String) -> Void)?

    public private(set) var state: State = .idle
    public private(set) var allowsRemoteInput = false
    public private(set) var screenSize: CGSize = .zero
    public private(set) var pendingFileOfferID: String?
    public private(set) var pendingFileOfferName: String?

    public var hasPendingFileOffer: Bool {
        pendingFileOfferID != nil && pendingFileOfferName != nil
    }

    private var session: UltraViewerRelaySession?
    private var eventsTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var configuration: Configuration?
    private var autoReconnect = false
    private var reconnectAttempt = 0
    private var peer: UltraViewerRelaySession.Peer?
    private var warnedAboutInputPermission = false
    private var reportedFirstPointer = false

    public init() {}

    // MARK: - Lifecycle

    /// Starts a session and, when asked, keeps retrying after an unexpected drop.
    public func connect(configuration: Configuration, autoReconnect: Bool = false) async {
        guard state == .idle else { return }
        self.configuration = configuration
        self.autoReconnect = autoReconnect
        self.reconnectAttempt = 0
        await start(configuration, isRetry: false)
    }

    /// Starts again with the last credentials after a drop or a manual request.
    public func reconnect() async {
        guard let configuration else {
            log("Chưa có phiên để kết nối lại.")
            return
        }
        autoReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        let current = session
        session = nil
        await current?.close()
        resetTransientState()
        reconnectAttempt = 0
        setState(.idle)
        log("Đang kết nối lại theo yêu cầu…")
        await start(configuration, isRetry: true)
    }

    public func disconnect() async {
        autoReconnect = false
        configuration = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        eventsTask?.cancel()
        eventsTask = nil
        let current = session
        session = nil
        await current?.close()
        resetTransientState()
        setState(.idle)
    }

    private func start(_ configuration: Configuration, isRetry: Bool) async {
        let sessionConfiguration = UltraViewerRelaySession.Configuration(
            registration: configuration.registration,
            commandHost: configuration.commandHost,
            listenerPort: configuration.listenerPort,
            localScreenWidth: configuration.localScreenWidth,
            localScreenHeight: configuration.localScreenHeight,
            displayName: configuration.displayName,
            captureDirectory: configuration.captureDirectory,
            enableLANDirect: configuration.enableLANDirect
        )
        let session = UltraViewerRelaySession()
        let stream: AsyncThrowingStream<UltraViewerRelaySession.Event, any Swift.Error>
        do {
            stream = try await session.connect(configuration: sessionConfiguration,
                                               partnerID: configuration.partnerID,
                                               password: configuration.password)
        } catch {
            log("Không bắt đầu được phiên: \(error.localizedDescription)")
            setState(.idle)
            scheduleReconnect()
            return
        }

        self.session = session
        resetTransientState()
        setState(.connecting)
        log(isRetry
            ? "Đang kết nối lại với \(configuration.partnerID)…"
            : "Đang tìm \(configuration.partnerID) qua dịch vụ UltraViewer…")

        eventsTask = Task { [weak self] in
            do {
                for try await event in stream {
                    await MainActor.run { self?.handle(event) }
                }
                await MainActor.run { self?.sessionEnded(reason: nil) }
            } catch is CancellationError {
                // Expected when the user taps Ngắt or asks for a reconnect.
            } catch {
                await MainActor.run { self?.sessionEnded(reason: error.localizedDescription) }
            }
        }
    }

    private func sessionEnded(reason: String?) {
        guard session != nil || state != .idle else { return }
        eventsTask = nil
        session = nil
        resetTransientState()
        setState(.idle)
        if let reason { log("Phiên kết thúc: \(reason)") }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard autoReconnect, let configuration, reconnectTask == nil else { return }
        reconnectAttempt += 1
        let delay = min(15.0, pow(2.0, Double(min(reconnectAttempt, 4))))
        log("Mất kết nối, thử lại sau \(Int(delay)) giây…")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.reconnectTask = nil
            guard self.state == .idle, self.autoReconnect else { return }
            await self.start(configuration, isRetry: true)
        }
    }

    private func resetTransientState() {
        peer = nil
        allowsRemoteInput = false
        screenSize = .zero
        pendingFileOfferID = nil
        pendingFileOfferName = nil
        warnedAboutInputPermission = false
        reportedFirstPointer = false
        onPermission?(false)
    }

    private func setState(_ newState: State) {
        guard state != newState else { return }
        state = newState
        onState?(newState)
    }

    private func handle(_ event: UltraViewerRelaySession.Event) {
        switch event {
        case let .status(text):
            log(text)
        case let .accepted(newPeer):
            peer = newPeer
            screenSize = CGSize(width: newPeer.width, height: newPeer.height)
            setState(.connected)
            applyInputPermission(newPeer.allowsRemoteInput)
        case let .screenChanged(newPeer):
            peer = newPeer
            screenSize = CGSize(width: newPeer.width, height: newPeer.height)
            applyInputPermission(newPeer.allowsRemoteInput)
            log("Màn hình máy Windows đổi kích thước: \(newPeer.width)×\(newPeer.height).")
        case let .inputPermission(allowed):
            applyInputPermission(allowed)
        case let .fileOffer(offer):
            pendingFileOfferID = offer.transferID
            pendingFileOfferName = offer.fileName
        default:
            break
        }
        onEvent?(event)
    }

    private func applyInputPermission(_ allowed: Bool) {
        guard allowsRemoteInput != allowed else { return }
        allowsRemoteInput = allowed
        if allowed { warnedAboutInputPermission = false }
        onPermission?(allowed)
        log(allowed
            ? "Điều khiển từ xa đã được cho phép."
            : "Chỉ xem; điều khiển từ xa tạm dừng.")
    }

    private func log(_ text: String) {
        onLog?(text)
    }

    // MARK: - Input

    /// Pointer events are queued into one ordered batch so a click cannot be
    /// interleaved with another gesture on a busy relay connection.
    public func sendPointer(_ kind: RemotePointerKind, at point: CGPoint) {
        guard session != nil else { return }
        if !reportedFirstPointer {
            reportedFirstPointer = true
            log("Đã nhận cử chỉ, đang kiểm tra quyền điều khiển từ máy Windows.")
        }
        guard allowsRemoteInput else {
            if !warnedAboutInputPermission {
                warnedAboutInputPermission = true
                log("Chưa có quyền điều khiển từ máy Windows. Hãy cho phép điều khiển trong UltraViewer bên Windows.")
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
        let payloads = messages.map { $0.encode() }
        Task { [weak self] in
            await self?.sendBatch(payloads, failurePrefix: "Không gửi được lệnh chuột")
        }
    }

    /// Sends already-encoded commands in order; useful for callers that build
    /// their own macro of keyboard and mouse messages.
    public func sendInputs(_ payloads: [Data]) async {
        await sendBatch(payloads, failurePrefix: "Không gửi được lệnh gộp")
    }

    private func sendBatch(_ payloads: [Data], failurePrefix: String) async {
        guard let session else { return }
        for payload in payloads {
            do {
                try await session.send(payload)
            } catch {
                log("\(failurePrefix): \(error.localizedDescription)")
                return
            }
        }
    }

    // MARK: - Session tools

    public func sendChat(_ text: String) async {
        guard let session else {
            log("Chưa có phiên kết nối để gửi tin nhắn.")
            return
        }
        guard !text.isEmpty else {
            log("Nhập nội dung tin nhắn trước khi gửi.")
            return
        }
        do {
            try await session.sendChat(text)
            log("Đã gửi tin nhắn.")
        } catch {
            log("Không gửi được tin nhắn: \(error.localizedDescription)")
        }
    }

    public func sendClipboardText(_ text: String) async {
        guard let session else {
            log("Chưa có phiên kết nối để gửi bảng nhớ tạm.")
            return
        }
        do {
            try await session.setClipboardSharing(true)
            try await session.sendClipboard(text)
            log("Đã gửi bảng nhớ tạm (\(text.utf8.count) byte).")
        } catch {
            log("Không gửi được bảng nhớ tạm: \(error.localizedDescription)")
        }
    }

    public func sendKeyboardText(_ text: String) async {
        guard let session else {
            log("Chưa có phiên kết nối để gửi bàn phím.")
            return
        }
        guard !text.isEmpty else {
            log("Không có nội dung để gửi qua bàn phím.")
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
                log("Không gửi được bàn phím: \(error.localizedDescription)")
                return
            }
        }
        log("Đã gửi bàn phím (chưa kiểm chứng trên Windows).")
    }

    public func sendFile(at url: URL) async {
        guard let session else {
            log("Chưa có phiên kết nối để gửi tệp.")
            return
        }
        do {
            let offer = try await session.sendFile(url)
            log("Đã gửi tệp \(offer.fileName) (mã \(offer.transferID)).")
        } catch {
            log("Không gửi được tệp \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    public func acceptLastFileOffer(to directory: URL) async {
        guard let session else {
            log("Chưa có phiên kết nối để nhận tệp.")
            return
        }
        guard let id = pendingFileOfferID, let name = pendingFileOfferName else {
            log("Chưa có đề nghị gửi tệp nào để nhận.")
            return
        }
        let destination = Self.safeDestination(for: name, in: directory)
        do {
            try await session.acceptFile(id, to: destination)
            pendingFileOfferID = nil
            pendingFileOfferName = nil
            log("Đang nhận \(destination.lastPathComponent) (mã \(id)).")
        } catch {
            log("Không nhận được tệp \(name): \(error.localizedDescription)")
        }
    }

    public func setComputerAudioEnabled(_ enabled: Bool) async {
        guard let session else {
            log("Chưa có phiên kết nối để đổi âm thanh máy tính.")
            return
        }
        do {
            try await session.setComputerAudioEnabled(enabled)
            log(enabled
                ? "Đã gửi yêu cầu bật âm thanh máy tính (bản iOS chưa phát âm thanh)."
                : "Đã gửi yêu cầu tắt âm thanh máy tính.")
        } catch {
            log("Không đổi được âm thanh máy tính: \(error.localizedDescription)")
        }
    }

    public func setCursorPositionsEnabled(_ enabled: Bool) async {
        guard session != nil else {
            log("Chưa có phiên kết nối để đổi vị trí con trỏ.")
            return
        }
        do {
            try await sendCommand(RemoteControlCommands.cursorPositions(enabled: enabled),
                                  requiresControl: false)
            log(enabled ? "Đã bật gửi vị trí con trỏ." : "Đã tắt gửi vị trí con trỏ.")
        } catch {
            log("Không đổi được vị trí con trỏ: \(error.localizedDescription)")
        }
    }

    public func setQuality(_ preset: RemoteControlCommands.QualityPreset) async {
        guard session != nil else {
            log("Chưa có phiên kết nối để đổi chất lượng.")
            return
        }
        do {
            for message in RemoteControlCommands.qualityPreset(preset) {
                try await sendCommand(message, requiresControl: false)
            }
            log("Đã gửi thiết lập chất lượng: \(Self.qualityLabel(preset)).")
        } catch {
            log("Không đổi được chất lượng: \(error.localizedDescription)")
        }
    }

    public func setWallpaperVisible(_ visible: Bool) async {
        guard session != nil else {
            log("Chưa có phiên kết nối để đổi hình nền.")
            return
        }
        do {
            try await sendCommand(RemoteControlCommands.wallpaper(visible: visible),
                                  requiresControl: false)
            log(visible ? "Đã gửi yêu cầu hiện hình nền." : "Đã gửi yêu cầu ẩn hình nền.")
        } catch {
            log("Không đổi được hình nền: \(error.localizedDescription)")
        }
    }

    public func sendAction(_ action: RemoteControlCommands.Action) async {
        guard session != nil else {
            log("Chưa có phiên kết nối để gửi lệnh.")
            return
        }
        guard allowsRemoteInput else {
            if !warnedAboutInputPermission {
                warnedAboutInputPermission = true
                log("Chưa có quyền điều khiển từ máy Windows. Hãy cho phép điều khiển trong UltraViewer bên Windows.")
            }
            return
        }
        do {
            try await sendCommand(RemoteControlCommands.action(action), requiresControl: true)
            log("Đã gửi lệnh \(String(describing: action)) (chưa kiểm chứng trên Windows).")
        } catch {
            log("Không gửi được lệnh \(String(describing: action)): \(error.localizedDescription)")
        }
    }

    /// Re-asks the Windows host for interactive control without dropping the session.
    public func requestControlPermission() async {
        guard let session else {
            log("Chưa có phiên kết nối để xin quyền điều khiển.")
            return
        }
        log("Đang gửi lại yêu cầu quyền điều khiển tới máy Windows…")
        do {
            try await session.requestRemoteControl()
            log("Đã gửi yêu cầu. Nếu Windows hỏi, hãy chọn cho phép điều khiển.")
        } catch {
            log("Không gửi được yêu cầu quyền điều khiển: \(error.localizedDescription)")
        }
    }

    public func requestSideSwitch(ownID: String, password: String) async {
        guard session != nil else {
            log("Chưa có phiên kết nối để đổi chiều điều khiển.")
            return
        }
        let message: RemoteControlCommands.Message
        do {
            message = try RemoteControlCommands.sideSwitch(ownID: ownID, password: password)
        } catch {
            log("Không gửi được yêu cầu đổi chiều: \(error.localizedDescription)")
            return
        }
        log("Đang gửi ID và mật khẩu phiên của mình sang máy Windows để đổi chiều điều khiển.")
        do {
            try await sendCommand(message, requiresControl: false)
            log("Đã gửi thông tin đăng nhập của mình sang máy Windows (chỉ thực hiện sau khi bạn xác nhận).")
        } catch {
            log("Không gửi được yêu cầu đổi chiều: \(error.localizedDescription)")
        }
    }

    private func sendCommand(_ message: RemoteControlCommands.Message,
                             requiresControl: Bool) async throws {
        guard let session else { return }
        try await session.sendCommand(message, requiresControl: requiresControl)
    }

    // MARK: - Helpers

    private static func qualityLabel(_ preset: RemoteControlCommands.QualityPreset) -> String {
        switch preset {
        case .automatic: return "tự động"
        case .speed: return "ưu tiên tốc độ"
        case .quality: return "ưu tiên chất lượng"
        @unknown default: return String(describing: preset)
        }
    }

    private static func safeDestination(for name: String, in directory: URL) -> URL {
        let components = name.components(separatedBy: CharacterSet(charactersIn: "/\\"))
        let base = components.last(where: { !$0.isEmpty && $0 != "." && $0 != ".." }) ?? "received-file"
        let manager = FileManager.default
        let nsBase = base as NSString
        let stem = nsBase.deletingPathExtension
        let ext = nsBase.pathExtension
        var candidate = directory.appendingPathComponent(base)
        var index = 1
        while manager.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? " (\(index))" : " (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(stem + suffix)
            index += 1
        }
        return candidate
    }
}
