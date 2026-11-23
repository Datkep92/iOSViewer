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

    private var session: UltraViewerRelaySession?
    private var eventsTask: Task<Void, Never>?
    private var peer: UltraViewerRelaySession.Peer?
    private var inputAllowed = false
    private static let maximumLogLines = 200

    public init() {}

    public func connect(partnerID: String, password: String) {
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
            stream = try session.connect(configuration: configuration, partnerID: id, password: password)
        } catch {
            report("Không bắt đầu được phiên: \(error.localizedDescription)")
            return
        }

        self.session = session
        self.peer = nil
        self.inputAllowed = false
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
        peer = nil
        state = .idle
        onState?(state)
        report("Đã ngắt phiên.")
    }

    /// Coordinates are already in Windows desktop pixels; the view maps the
    /// touch point into that space before calling here.
    public func sendPointer(_ kind: RemotePointerKind, at point: CGPoint) {
        guard inputAllowed, let session else { return }
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

    private func handle(_ event: UltraViewerRelaySession.Event) {
        switch event {
        case let .status(text):
            report(text)
        case let .accepted(newPeer):
            peer = newPeer
            state = .connected
            onState?(state)
            report("Đã kết nối \(newPeer.width)×\(newPeer.height).")
        case let .screenChanged(newPeer):
            peer = newPeer
            report("Màn hình máy Windows đổi kích thước: \(newPeer.width)×\(newPeer.height).")
        case let .frame(latest):
            guard let bitmap = latest.take(), let image = bitmap.makeCGImage() else { return }
            let size = peer.map { CGSize(width: $0.width, height: $0.height) }
                ?? CGSize(width: bitmap.width, height: bitmap.height)
            onFrame?(image, size)
        case let .inputPermission(allowed):
            inputAllowed = allowed
            report(allowed ? "Điều khiển từ xa đã được cho phép." : "Chỉ xem; điều khiển từ xa tạm dừng.")
        case let .chat(text):
            report("Tin nhắn: \(text)")
        case let .typing(typing):
            if typing { report("Bên kia đang gõ…") }
        case let .clipboard(text):
            report("Bảng nhớ tạm (\(text.utf8.count} byte) — chưa có giao diện sao chép.")
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
            report("Nhận đề nghị gửi tệp \(offer.fileName) — chưa hỗ trợ truyền tệp.")
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
