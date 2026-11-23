import UIKit

/// Cần điều khiển ảo: kéo núm tròn để đẩy con trỏ Windows theo mọi hướng.
public final class RemoteJoystickView: UIView {
    public var onVector: ((CGVector) -> Void)?

    private let thumb = UIView()
    private let pan = UIPanGestureRecognizer()
    private var timer: Timer?
    private var vector: CGVector = .zero
    private static let radius: CGFloat = 42

    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = UIColor.white.withAlphaComponent(0.10)
        layer.cornerRadius = 60
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "remote-joystick"
        accessibilityLabel = "Cần điều khiển con trỏ"

        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.75)
        thumb.layer.cornerRadius = 20
        addSubview(thumb)
        pan.addTarget(self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        thumb.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        thumb.center = center(of: vector)
    }

    private func center(of vector: CGVector) -> CGPoint {
        CGPoint(x: bounds.midX + vector.dx * Self.radius,
                y: bounds.midY + vector.dy * Self.radius)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let location = recognizer.location(in: self)
            let dx = (location.x - bounds.midX) / Self.radius
            let dy = (location.y - bounds.midY) / Self.radius
            let length = hypot(dx, dy)
            let scale = length > 1 ? 1 / length : 1
            vector = CGVector(dx: dx * scale, dy: dy * scale)
            thumb.center = center(of: vector)
            startTimer()
        default:
            vector = .zero
            thumb.center = CGPoint(x: bounds.midX, y: bounds.midY)
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        // 30 lần mỗi giây đủ mượt mà không làm nghẽn luồng giao diện.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.vector.dx != 0 || self.vector.dy != 0 else { return }
            self.onVector?(self.vector)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        if newSuperview == nil { stopTimer() }
        super.willMove(toSuperview: newSuperview)
    }
}
