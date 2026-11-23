import CoreGraphics
import UIKit

public enum RemotePointerKind: Sendable {
    case move, leftClick, doubleClick, rightClick
}

/// Displays the newest decoded Windows screen and maps touches into remote
/// desktop pixels. A long press is the iOS stand-in for a right click.
public final class RemoteScreenImageView: UIImageView {
    public var remoteSize: CGSize = .zero
    public var onPointer: ((RemotePointerKind, CGPoint) -> Void)?

    private let singleTap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()

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
        singleTap.addTarget(self, action: #selector(handleSingleTap(_:)))
        doubleTap.addTarget(self, action: #selector(handleDoubleTap(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.addTarget(self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(singleTap)
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(longPress)
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
