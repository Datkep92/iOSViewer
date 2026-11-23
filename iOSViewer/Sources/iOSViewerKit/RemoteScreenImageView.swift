import CoreGraphics
import UIKit

public enum RemotePointerKind: Sendable {
    case move, leftClick, doubleClick, rightClick
    /// One Windows wheel notch is a signed multiple of 120 in the high word.
    case wheel(delta: Int16)
    case horizontalWheel(delta: Int16)
}

/// Displays the newest decoded Windows screen and maps touches into remote
/// desktop pixels. A long press is the iOS stand-in for a right click; a
/// two-finger swipe stands in for the mouse wheel at 1x and pans the zoomed
/// image above 1x. A pinch zooms from 1x to 4x.
public final class RemoteScreenImageView: UIImageView, UIGestureRecognizerDelegate {
    public var remoteSize: CGSize = .zero
    public var onPointer: ((RemotePointerKind, CGPoint) -> Void)?

    /// 1 is aspect-fit, 4 is the maximum. Change it through the zoom API below.
    public private(set) var zoomScale: CGFloat = 1

    private let singleTap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()
    private let movePan = UIPanGestureRecognizer()
    private let scrollPan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private static let pointsPerWheelNotch: CGFloat = 36
    private static let minimumZoom: CGFloat = 1
    private static let maximumZoom: CGFloat = 4
    private var lastScrollTranslationX: CGFloat = 0
    private var lastScrollTranslationY: CGFloat = 0
    private var lastZoomPanTranslation: CGPoint = .zero
    private var panOffset: CGPoint = .zero
    private var pinchStartScale: CGFloat = 1

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit
        backgroundColor = .black
        clipsToBounds = true
        singleTap.numberOfTapsRequired = 1
        doubleTap.numberOfTapsRequired = 2
        singleTap.require(toFail: doubleTap)
        singleTap.require(toFail: longPress)
        singleTap.require(toFail: movePan)
        singleTap.addTarget(self, action: #selector(handleSingleTap(_:)))
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        movePan.minimumNumberOfTouches = 1
        movePan.maximumNumberOfTouches = 1
        movePan.addTarget(self, action: #selector(handleMove(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2
        scrollPan.addTarget(self, action: #selector(handleScroll(_:)))
        pinch.addTarget(self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(longPress)
        addGestureRecognizer(movePan)
        addGestureRecognizer(scrollPan)
        addGestureRecognizer(pinch)
    }

    /// A pinch and a two-finger pan both use two touches. Let UIKit deliver
    /// both, then ignore the pan while the pinch is active so they never
    /// fight over the same transform.
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                                  shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        (gestureRecognizer === pinch && otherGestureRecognizer === scrollPan) ||
        (gestureRecognizer === scrollPan && otherGestureRecognizer === pinch)
    }

    @objc private func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let point = remotePoint(from: recognizer.location(in: self)) else { return }
        onPointer?(.leftClick, point)
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let point = remotePoint(from: recognizer.location(in: self)) else { return }
        onPointer?(.doubleClick, point)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let point = remotePoint(from: recognizer.location(in: self)) else { return }
        onPointer?(.rightClick, point)
    }

    /// One-finger drag moves the remote pointer without holding a mouse button.
    @objc private func handleMove(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            guard let point = remotePoint(from: recognizer.location(in: self)) else { return }
            onPointer?(.move, point)
        default:
            break
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            pinchStartScale = zoomScale
        case .changed:
            setZoomScale(pinchStartScale * recognizer.scale, animated: false)
        default:
            pinchStartScale = Self.minimumZoom
        }
    }

    /// Two-finger vertical (and horizontal) swipes send wheel notches at 1x;
    /// above 1x the same gesture pans the zoomed content instead.
    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            lastScrollTranslationX = translation.x
            lastScrollTranslationY = translation.y
            lastZoomPanTranslation = translation
        case .changed:
            if zoomScale > Self.minimumZoom {
                guard pinch.state != .began, pinch.state != .changed else {
                    lastZoomPanTranslation = translation
                    return
                }
                let offset = CGPoint(x: panOffset.x + translation.x - lastZoomPanTranslation.x,
                                     y: panOffset.y + translation.y - lastZoomPanTranslation.y)
                panOffset = clampedOffset(offset, scale: zoomScale)
                lastZoomPanTranslation = translation
                applyTransform()
                return
            }
            guard pinch.state != .began, pinch.state != .changed else {
                lastScrollTranslationX = translation.x
                lastScrollTranslationY = translation.y
                return
            }
            let vertical = notches(for: translation.y, previous: lastScrollTranslationY)
            if vertical != 0, let point = remotePoint(from: recognizer.location(in: self)) {
                lastScrollTranslationY -= CGFloat(vertical) * Self.pointsPerWheelNotch
                onPointer?(.wheel(delta: Int16(clamping: vertical * 120)), point)
            }
            let horizontal = notches(for: translation.x, previous: lastScrollTranslationX)
            if horizontal != 0, let point = remotePoint(from: recognizer.location(in: self)) {
                lastScrollTranslationX -= CGFloat(horizontal) * Self.pointsPerWheelNotch
                onPointer?(.horizontalWheel(delta: Int16(clamping: horizontal * 120)), point)
            }
        default:
            lastScrollTranslationX = 0
            lastScrollTranslationY = 0
            lastZoomPanTranslation = .zero
        }
    }

    private func notches(for travel: CGFloat, previous: CGFloat) -> Int {
        Int((previous - travel) / Self.pointsPerWheelNotch)
    }

    // MARK: - Public zoom API

    public func zoomIn() {
        setZoomScale(zoomScale * 1.25, animated: true)
    }

    public func zoomOut() {
        setZoomScale(zoomScale / 1.25, animated: true)
    }

    public func resetZoom() {
        setZoomScale(Self.minimumZoom, animated: true)
    }

    public func setZoomScale(_ scale: CGFloat, animated: Bool) {
        let target = min(max(scale, Self.minimumZoom), Self.maximumZoom)
        let apply = { [weak self] in
            guard let self else { return }
            self.zoomScale = target
            self.panOffset = target <= Self.minimumZoom ? .zero : self.clampedOffset(self.panOffset, scale: target)
            self.applyTransform()
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: apply)
        } else {
            apply()
        }
    }

    /// Scale around the centre, then translate inside the overscroll limit.
    private func applyTransform() {
        let centre = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        transform = CGAffineTransform.identity
            .translatedBy(x: centre.x + panOffset.x, y: centre.y + panOffset.y)
            .scaledBy(x: zoomScale, y: zoomScale)
            .translatedBy(x: -centre.x, y: -centre.y)
    }

    private func clampedOffset(_ offset: CGPoint, scale: CGFloat) -> CGPoint {
        guard scale > Self.minimumZoom else { return .zero }
        let maxX = bounds.width * (scale - 1) / 2
        let maxY = bounds.height * (scale - 1) / 2
        return CGPoint(x: min(max(offset.x, -maxX), maxX),
                       y: min(max(offset.y, -maxY), maxY))
    }

    /// Undoes the aspect-fit transform so a tap lands on the right desktop pixel.
    /// `location(in:)` already inverts the view transform, so zoomed touches
    /// still arrive here in the untransformed bounds.
    public func remotePoint(from location: CGPoint) -> CGPoint? {
        guard let image, image.size.width > 0, image.size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (bounds.width - drawn.width) / 2,
                             y: (bounds.height - drawn.height) / 2)
        let local = CGPoint(x: (location.x - origin.x) / scale,
                            y: (location.y - origin.y) / scale)
        guard local.x >= 0, local.y >= 0,
              local.x <= image.size.width, local.y <= image.size.height else { return nil }
        let desktop = remoteSize.width > 0 && remoteSize.height > 0 ? remoteSize : image.size
        return CGPoint(x: min(max(local.x / image.size.width * desktop.width, 0), desktop.width - 1),
                       y: min(max(local.y / image.size.height * desktop.height, 0), desktop.height - 1))
    }
}
