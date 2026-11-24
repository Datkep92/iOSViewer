import UIKit
import RemoteControlKit
import CoreGraphics

/// Ảnh màn hình Windows với các cử chỉ điều khiển và zoom.
/// - absolute: chạm vào đâu thì gửi lệnh chuột tới điểm đó.
/// - trackpad: vuốt để đẩy một con trỏ ảo, chạm để click tại con trỏ đó.
/// - joystick: cần điều khiển ở góc màn hình đẩy con trỏ ảo liên tục.
public final class RemoteScreenImageView: UIImageView {
    public var remoteSize: CGSize = .zero {
        didSet { updateCursorOverlay() }
    }
    public var onPointer: ((RemotePointerKind, CGPoint) -> Void)?
    public var mode: RemotePointerMode = .absolute {
        didSet { virtualCursor = nil; updateCursorOverlay() }
    }
    public private(set) var zoomScale: CGFloat = 1

    private let singleTap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()
    private let movePan = UIPanGestureRecognizer()
    private let scrollPan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let cursorView = UIView()

    private var virtualCursor: CGPoint?
    private var lastTrackpadTranslation: CGPoint = .zero
    /// Độ dời của tâm ảnh đã phóng to (toạ độ màn hình, chưa nhân tỉ lệ).
    private var contentOffset = CGPoint.zero
    private var pinchAnchor: CGPoint?     // điểm trong bounds nằm dưới hai ngón lúc bắt đầu chổm
    private var pinchStartScale: CGFloat = 1
    private var pinchStartOffset = CGPoint.zero
    private var isPinching = false
    private var lastZoomPanTranslation: CGPoint = .zero
    private static let pointsPerWheelNotch: CGFloat = 36
    private static let minimumZoom: CGFloat = 1
    private static let maximumZoom: CGFloat = 4

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configureGestures()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGestures()
    }

    private func configureGestures() {
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit
        backgroundColor = .black

        cursorView.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        cursorView.layer.cornerRadius = 10
        cursorView.layer.borderWidth = 2
        cursorView.layer.borderColor = UIColor.white.cgColor
        cursorView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        cursorView.isHidden = true
        cursorView.isUserInteractionEnabled = false
        addSubview(cursorView)

        singleTap.addTarget(self, action: #selector(handleSingleTap(_:)))
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        movePan.addTarget(self, action: #selector(handleMove(_:)))
        scrollPan.addTarget(self, action: #selector(handleScroll(_:)))
        pinch.addTarget(self, action: #selector(handlePinch(_:)))

        singleTap.numberOfTapsRequired = 1
        doubleTap.numberOfTapsRequired = 2
        longPress.minimumPressDuration = 0.45
        movePan.minimumNumberOfTouches = 1
        movePan.maximumNumberOfTouches = 1
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2

        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: longPress)
        doubleTap.require(toFail: longPress)

        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(longPress)
        addGestureRecognizer(movePan)
        addGestureRecognizer(scrollPan)
        addGestureRecognizer(pinch)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateCursorOverlay()
    }

    public func setRemoteFrame(_ size: CGSize) {
        remoteSize = size
        virtualCursor = nil
        updateCursorOverlay()
    }

    public func setImage(_ image: UIImage?, remoteSize size: CGSize) {
        self.image = image
        setRemoteFrame(size)
    }

    private func remotePoint(from location: CGPoint) -> CGPoint? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let desktop = effectiveDesktopSize
        guard desktop.width > 0, desktop.height > 0 else { return nil }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawnWidth = image.size.width * scale
        let drawnHeight = image.size.height * scale
        let originX = (bounds.width - drawnWidth) / 2
        let originY = (bounds.height - drawnHeight) / 2
        let localX = (location.x - originX) / drawnWidth
        let localY = (location.y - originY) / drawnHeight
        let x = min(max(localX, 0), 1) * desktop.width
        let y = min(max(localY, 0), 1) * desktop.height
        return CGPoint(x: x, y: y)
    }

    /// Ngược lại với remotePoint: từ toạ độ Windows sang điểm trên ảnh.
    public func viewPoint(fromDesktop point: CGPoint) -> CGPoint? {
        guard let image, image.size.width > 0, image.size.height > 0,
              let drawn = drawnImageSize(), drawn.width > 0, drawn.height > 0 else { return nil }
        let desktop = effectiveDesktopSize
        guard desktop.width > 0, desktop.height > 0 else { return nil }
        let origin = CGPoint(x: (bounds.width - drawn.width) / 2,
                             y: (bounds.height - drawn.height) / 2)
        return CGPoint(x: origin.x + point.x / desktop.width * drawn.width,
                       y: origin.y + point.y / desktop.height * drawn.height)
    }

    private var effectiveDesktopSize: CGSize {
        remoteSize.width > 0 && remoteSize.height > 0 ? remoteSize : (image?.size ?? .zero)
    }

    private func drawnImageSize() -> CGSize? {
        guard let image, bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func updateCursorOverlay() {
        guard mode != .absolute, let cursor = virtualCursor,
              let point = viewPoint(fromDesktop: cursor) else {
            cursorView.isHidden = true
            return
        }
        cursorView.isHidden = false
        cursorView.center = point
    }

    /// Chế độ trackpad/joystick dùng điểm này làm con trỏ Windows hiện tại.
    public func moveVirtualCursor(by viewDelta: CGPoint) {
        guard let drawn = drawnImageSize(), drawn.width > 0, drawn.height > 0 else { return }
        let desktop = effectiveDesktopSize
        guard desktop.width > 0, desktop.height > 0 else { return }
        if virtualCursor == nil {
            virtualCursor = CGPoint(x: desktop.width / 2, y: desktop.height / 2)
            updateCursorOverlay()
        }
        let dx = viewDelta.x / drawn.width * desktop.width
        let dy = viewDelta.y / drawn.height * desktop.height
        let current = virtualCursor!
        virtualCursor = CGPoint(x: min(max(current.x + dx, 0), max(0, desktop.width - 1)),
                                y: min(max(current.y + dy, 0), max(0, desktop.height - 1)))
        updateCursorOverlay()
        onPointer?(.move, virtualCursor!)
    }

    /// Với chế độ trackpad/joystick, click luôn gửi tới con trỏ ảo.
    /// Cúm chạm đầu tiên khởi tạo con trỏ tại điểm đang chạm.
    private func clickPoint(for recognizer: UIGestureRecognizer) -> CGPoint? {
        if mode == .absolute { return remotePoint(from: recognizer.location(in: self)) }
        if virtualCursor == nil, let point = remotePoint(from: recognizer.location(in: self)) {
            virtualCursor = point
            updateCursorOverlay()
        }
        return virtualCursor
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard let point = clickPoint(for: recognizer) else { return }
        onPointer?(.leftClick, point)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard let point = clickPoint(for: recognizer) else { return }
        onPointer?(.doubleClick, point)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let point = clickPoint(for: recognizer) else { return }
        onPointer?(.rightClick, point)
    }

    @objc private func handleMove(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            lastTrackpadTranslation = translation
        case .changed:
            if mode == .absolute, let point = remotePoint(from: recognizer.location(in: self)) {
                onPointer?(.move, point)
            } else if mode == .trackpad {
                let delta = CGPoint(x: translation.x - lastTrackpadTranslation.x,
                                    y: translation.y - lastTrackpadTranslation.y)
                lastTrackpadTranslation = translation
                moveVirtualCursor(by: delta)
            }
        default:
            lastTrackpadTranslation = .zero
        }
    }

    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        guard !isPinching else { return }
        if zoomScale > 1.01 {
            handleZoomPan(recognizer)
            return
        }
        guard recognizer.state == .changed || recognizer.state == .began || recognizer.state == .ended else { return }
        let translation = recognizer.translation(in: self)
        let stepX = translation.x / Self.pointsPerWheelNotch
        let stepY = translation.y / Self.pointsPerWheelNotch
        let horizontal = abs(stepX) > abs(stepY)
        let notches = Int((horizontal ? stepX : stepY).rounded(.towardZero))
        guard notches != 0, let point = clickPoint(for: recognizer) else { return }
        if horizontal {
            onPointer?(.horizontalWheel(delta: Int16(clamping: notches)), point)
        } else {
            onPointer?(.wheel(delta: Int16(clamping: notches)), point)
        }
    }

    /// Khi đã phóng to, vuốt kéo ảnh đi theo hướng ngón tay thay vì gửi lệnh cuộn.
    private func handleZoomPan(_ recognizer: UIPanGestureRecognizer) {
        guard !isPinching else { return }
        switch recognizer.state {
        case .began:
            lastZoomPanTranslation = .zero
            recognizer.setTranslation(.zero, in: self)
        case .changed:
            let translation = recognizer.translation(in: self)
            // location(in:) trả toạ độ bounds sau khi đảo transform, nên nhân lại
            // theo tỉ lệ để được độ dời thật trên màn hình; cộng vào offset để ảnh đi cùng ngón.
            let delta = CGPoint(x: (translation.x - lastZoomPanTranslation.x) * zoomScale,
                                y: (translation.y - lastZoomPanTranslation.y) * zoomScale)
            lastZoomPanTranslation = translation
            contentOffset = clampOffset(CGPoint(x: contentOffset.x + delta.x,
                                                y: contentOffset.y + delta.y),
                                        scale: zoomScale)
            applyTransform()
        default:
            lastZoomPanTranslation = .zero
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPinching = true
            pinchStartScale = zoomScale
            pinchStartOffset = contentOffset
            // location(in:) là điểm trong bounds nằm dưới hai ngón; giữ đúng điểm
            // này cố định trên màn hình trong suốt cú chổm.
            pinchAnchor = recognizer.location(in: self)
        case .changed:
            guard let anchor = pinchAnchor else { return }
            let next = min(max(pinchStartScale * recognizer.scale,
                               Self.minimumZoom), Self.maximumZoom)
            applyZoom(next, fromScale: pinchStartScale,
                      fromOffset: pinchStartOffset, anchorBounds: anchor)
        default:
            isPinching = false
            pinchAnchor = nil
        }
    }

    public func setZoomScale(_ scale: CGFloat, animated: Bool = false,
                             at focusPoint: CGPoint? = nil) {
        let next = min(max(scale, Self.minimumZoom), Self.maximumZoom)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        applyZoom(next, fromScale: zoomScale, fromOffset: contentOffset,
                  anchorBounds: focusPoint ?? center)
    }

    /// Với ánh xạ `p_super = center + s·(p - center) + offset`, muốn điểm
    /// `anchorBounds` đứng yên thì offset mới = offset cũ + (s cũ - s mới)·(anchor - center).
    private func applyZoom(_ next: CGFloat, fromScale: CGFloat,
                           fromOffset: CGPoint, anchorBounds: CGPoint) {
        if next <= Self.minimumZoom {
            zoomScale = Self.minimumZoom
            contentOffset = .zero
            transform = .identity
            return
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let change = fromScale - next
        let offset = CGPoint(x: fromOffset.x + change * (anchorBounds.x - center.x),
                             y: fromOffset.y + change * (anchorBounds.y - center.y))
        zoomScale = next
        contentOffset = clampOffset(offset, scale: next)
        applyTransform()
    }

    public func zoomIn() {
        setZoomScale(zoomScale * 1.5)
    }

    public func zoomOut() {
        setZoomScale(zoomScale / 1.5)
    }

    public func resetZoom() {
        setZoomScale(Self.minimumZoom)
    }

    private func clampOffset(_ offset: CGPoint, scale: CGFloat) -> CGPoint {
        let maxX = bounds.width * (scale - 1) / 2
        let maxY = bounds.height * (scale - 1) / 2
        return CGPoint(x: min(max(offset.x, -maxX), maxX),
                       y: min(max(offset.y, -maxY), maxY))
    }

    /// Ma trận tường minh `M·v = s·v + offset`. Không kẹp lại lần thứ hai ở đây:
    /// mọi thay đổi đã đi qua `clampOffset`, nên chiều kéo không bị đảo.
    private func applyTransform() {
        transform = CGAffineTransform(a: zoomScale, b: 0, c: 0, d: zoomScale,
                                      tx: contentOffset.x, ty: contentOffset.y)
    }
}
