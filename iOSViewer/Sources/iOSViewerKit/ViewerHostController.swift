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
    private var lastGoodFrame: HostedScreenFrame?
    private var didReportDarkCapture = false

    var isRunning: Bool { running }

    func start() async throws {
        guard !running else { return }
        lastGoodFrame = nil
        didReportDarkCapture = false
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
            let frame = resolvedFrame()
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
        let frame = resolvedFrame()
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

    /// Khi app đang ở nền, `drawHierarchy` có thể trả ảnh đen. Đổi sang ảnh tốt
    /// gần nhất (hoặc ảnh mẫu) để Windows không thấy màn hình đen.
    private func resolvedFrame() -> HostedScreenFrame {
        let frame = frameProvider?() ?? Self.placeholderFrame()
        if !Self.isMostlyBlack(frame) {
            lastGoodFrame = frame
            return frame
        }
        if !didReportDarkCapture {
            didReportDarkCapture = true
            onStatus?("Không chụp được giao diện lúc này; dùng ảnh gần nhất để Windows không thấy màn hình đen.")
        }
        return lastGoodFrame ?? Self.placeholderFrame()
    }

    /// Đếm nhanh các điểm sáng trên dữ liệu RGB555 đã đóng gói.
    private static func isMostlyBlack(_ frame: HostedScreenFrame) -> Bool {
        let data = frame.rgb555BottomUp
        guard data.count >= 2 else { return true }
        var lit = 0
        var sampled = 0
        var index = 0
        while index + 1 < data.count {
            let value = UInt16(data[index]) | (UInt16(data[index + 1]) << 8)
            if value & 0x7FFF != 0 { lit += 1 }
            sampled += 1
            index += 32
        }
        return sampled == 0 || lit * 100 < sampled * 2
    }

    /// Chụp giao diện hiện tại của app, thu nhỏ để gửi nhanh qua relay.
    static func frame(from view: UIView) -> HostedScreenFrame {
        let width: Int = 480
        let height = max(160, min(960, Int(480 * view.bounds.height / max(view.bounds.width, 1))))
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            // Nền có hoa văn sáng: dù không chụp được giao diện (app ở nền), Windows
            // vẫn nhận được ảnh có nội dung thay vì một khung đen đặc.
            UIColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1).setFill()
            renderer.fill(CGRect(origin: .zero, size: size))
            UIColor.white.withAlphaComponent(0.10).setFill()
            for x in stride(from: 0, to: Int(size.width), by: 40) {
                for y in stride(from: 0, to: Int(size.height), by: 40) {
                    if (x / 40 + y / 40) % 2 == 0 {
                        renderer.fill(CGRect(x: x, y: y, width: 40, height: 40))
                    }
                }
            }
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
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
