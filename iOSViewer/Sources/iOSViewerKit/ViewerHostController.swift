import Foundation
import UIKit
import UltraViewerProtocol

/// Giữ một phiên đăng ký riêng để Windows có thể kết nối ngược vào iPhone bằng
/// ID số do relay cấp, không phải chuỗi định danh nội bộ 32 ký tự.
@MainActor
final class ViewerHostController {
    var onStatus: ((String) -> Void)?
    var onRequest: ((String) -> Void)?
    /// ID số do relay cấp và mật khẩu phiên — đây là thông tin Windows cần nhập.
    var onRegistered: ((String, String) -> Void)?
    var onConnected: ((String) -> Void)?
    /// Ảnh gửi cho Windows; nếu không có thì dùng ảnh mẫu.
    var frameProvider: (() -> HostedScreenFrame)?

    private let host = UltraViewerHostSession()
    private var events: Task<Void, Never>?
    private var running = false
    private var pendingRequest: UltraViewerHostSession.IncomingRequest?

    var isRunning: Bool { running }

    func start() async throws {
        guard !running else { return }
        let registration = try IOSRegistrationProfile.loadOrCreate()
        let stream = try await host.start(configuration: .init(
            registration: registration,
            listenerPort: 443))
        running = true
        events = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    await self.handle(event)
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.running = false
                    self.onStatus?("Nhận kết nối dừng: \(error.localizedDescription)")
                }
            }
            await MainActor.run { [weak self] in
                self?.running = false
            }
        }
    }

    func stop() async {
        guard running else { return }
        events?.cancel()
        events = nil
        await host.stop()
        running = false
        pendingRequest = nil
        onStatus?("Đã đóng chế độ nhận kết nối ngược.")
    }

    private func handle(_ event: UltraViewerHostSession.Event) async {
        switch event {
        case let .status(text):
            onStatus?("Máy nhận: \(text)")
        case let .registered(id):
            let password = (try? IOSRegistrationProfile.loadOrCreate().password) ?? ""
            onRegistered?(id, password)
        case let .request(request):
            pendingRequest = request
            onStatus?("Windows \(request.viewerID) xin kết nối vào iPhone — chờ bạn xác nhận.")
            onRequest?(request.viewerID)
        case let .connected(request):
            onConnected?(request.viewerID)
        case let .captureRequested(ticket):
            let frame = frameProvider?() ?? Self.placeholderFrame()
            do {
                try await host.submitFrame(frame, ticket: ticket)
            } catch {
                onStatus?("Gửi ảnh cho Windows không được: \(error.localizedDescription)")
            }
        case let .viewerEnded(reason):
            onStatus?("Windows đã ngắt kết nối ngược: \(reason ?? "không rõ lý do").")
        case let .input(_, payload):
            onStatus?("Nhận lệnh điều khiển từ Windows (\(payload.count) byte).")
        case .releaseInput, .sideSwitchRequested, .chat, .typing, .clipboard,
             .fileOffer, .fileProgress, .fileCompleted, .fileCanceled, .fileFailed:
            break
        }
    }

    func approvePending() async {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        let frame = frameProvider?() ?? Self.placeholderFrame()
        do {
            try await host.approve(request.id, firstFrame: frame, allowsControl: true)
            onStatus?("Đã chấp nhận Windows \(request.viewerID) điều khiển iPhone.")
        } catch {
            onStatus?("Không chấp nhận được: \(error.localizedDescription)")
        }
    }

    func declinePending() async {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        await host.decline(request.id)
        onStatus?("Đã từ chối Windows \(request.viewerID) kết nối ngược.")
    }

    // MARK: - Ảnh gửi cho Windows

    /// Chụp giao diện hiện tại của app, thu nhỏ để gửi nhanh qua relay.
    static func frame(from view: UIView) -> HostedScreenFrame {
        let width: Int = 480
        let height = max(160, min(960, Int(480 * view.bounds.height / max(view.bounds.width, 1))))
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.black.setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false)
        }
        return frame(from: image)
    }

    private static func frame(from image: UIImage) -> HostedScreenFrame {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        guard let cgImage = image.cgImage, width > 0, height > 0 else { return placeholderFrame() }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &rgba, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return placeholderFrame() }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = Data()
        pixels.reserveCapacity(width * height * 2)
        for row in 0..<height {
            let source = (height - 1 - row) * width * 4
            for column in 0..<width {
                let index = source + column * 4
                let value = UInt16(rgba[index + 2]) |
                    (UInt16(rgba[index + 1]) << 5) |
                    (UInt16(rgba[index]) << 10)
                pixels.append(UInt8(truncatingIfNeeded: value))
                pixels.append(UInt8(truncatingIfNeeded: value >> 8))
            }
        }
        return HostedScreenFrame(width: width, height: height, rgb555BottomUp: pixels,
                                 monitors: [HostedScreenMonitor(left: 0, top: 0,
                                                                right: Int32(width), bottom: Int32(height))],
                                 layoutIdentifier: "iOSViewer")
    }

    /// Ảnh mẫu khi chưa chụp được giao diện; vẫn cho Windows thấy kết nối có ảnh.
    static func placeholderFrame() -> HostedScreenFrame {
        let width = 480
        let height = 270
        var pixels = Data()
        pixels.reserveCapacity(width * height * 2)
        for row in 0..<height {
            for column in 0..<width {
                let red = UInt16(column * 31 / width)
                let green = UInt16(row * 31 / height)
                let blue = UInt16(12)
                let value = blue | (green << 5) | (red << 10)
                pixels.append(UInt8(truncatingIfNeeded: value))
                pixels.append(UInt8(truncatingIfNeeded: value >> 8))
            }
        }
        return HostedScreenFrame(width: width, height: height, rgb555BottomUp: pixels,
                                 monitors: [HostedScreenMonitor(left: 0, top: 0,
                                                                right: Int32(width), bottom: Int32(height))],
                                 layoutIdentifier: "iOSViewer")
    }
}
