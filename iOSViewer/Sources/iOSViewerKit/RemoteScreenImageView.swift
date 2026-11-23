import CoreGraphics
import UIKit

public enum RemotePointerKind: Sendable {
    case move, leftClick, doubleClick, rightClick
    /// One Windows wheel notch is a signed multiple of 120 in the high word.
    case wheel(delta: Int16)
}

/// Displays the newest decoded Windows screen and maps touches into remote
/// desktop pixels. A long press is the iOS stand-in for a right click; a
/// two-finger swipe stands in for the mouse wheel.
public final class RemoteScreenImageView: UIImageView {
    public var remoteSize: CGSize = .zero
    public var onPointer: ((RemotePointerKind, CGPoint) -> Void)?

    private let singleTap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()
    private let movePan = UIPanGestureRecognizer()
    private let scrollPan = UIPanGestureRecognizer()
    private static let pointsPerWheelNotch: CGFloat = 36
    private var lastScrollTranslationY: CGFloat = 0

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
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(longPress)
        addGestureRecognizer(movePan)
        addGestureRecognizer(scrollPan)
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

    /// Two-finger vertical swipe sends wheel notches to the remote desktop.
    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            lastScrollTranslationY = recognizer.translation(in: self).y
        case .changed:
            let current = recognizer.translation(in: self).y
            let travelled = lastScrollTranslationY - current
            let notches = Int(travelled / Self.pointsPerWheelNotch)
            guard notches != 0,
                  let point = remotePoint(from: recognizer.location(in: self)) else { return }
            lastScrollTranslationY -= CGFloat(notches) * Self.pointsPerWheelNotch
            onPointer?(.wheel(delta: Int16(clamping: notches * 120)), point)
        default:
            lastScrollTranslationY = 0
        }
    }

    /// Undoes the aspect-fit transform so a tap lands on the right desktop pixel.
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
