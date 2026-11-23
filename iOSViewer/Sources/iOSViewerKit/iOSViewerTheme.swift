import UIKit

/// Một bảng phối màu và vài tiện ích nhỏ để giao diện mới có cùng "chất".
/// Không dùng asset hay storyboard nên bản đóng gói vẫn chỉ cần Mach-O + Info.plist.
public enum ViewerTheme {
    public static let background = UIColor(red: 0.043, green: 0.059, blue: 0.098, alpha: 1)
    public static let panel = UIColor(red: 0.086, green: 0.114, blue: 0.180, alpha: 0.96)
    public static let panelSoft = UIColor(red: 0.118, green: 0.153, blue: 0.231, alpha: 0.92)
    public static let border = UIColor.white.withAlphaComponent(0.10)
    public static let text = UIColor.white
    public static let muted = UIColor.white.withAlphaComponent(0.58)
    public static let accent = UIColor(red: 0.043, green: 0.553, blue: 0.969, alpha: 1)
    public static let accentSoft = UIColor(red: 0.043, green: 0.553, blue: 0.969, alpha: 0.18)
    public static let success = UIColor(red: 0.102, green: 0.686, blue: 0.412, alpha: 1)
    public static let warning = UIColor(red: 0.902, green: 0.557, blue: 0.129, alpha: 1)
    public static let radius: CGFloat = 16

    public static func styleCard(_ view: UIView) {
        view.backgroundColor = panel
        view.layer.cornerRadius = radius
        view.layer.borderWidth = 1
        view.layer.borderColor = border.cgColor
    }

    public static func styleField(_ field: UITextField) {
        field.backgroundColor = panelSoft
        field.textColor = text
        field.tintColor = accent
        field.layer.cornerRadius = 12
        field.layer.borderWidth = 1
        field.layer.borderColor = border.cgColor
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.attributedPlaceholder = NSAttributedString(
            string: field.placeholder ?? "",
            attributes: [.foregroundColor: muted]
        )
    }

    public static func styleButton(_ button: UIButton, primary: Bool = false) {
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        if primary {
            button.backgroundColor = accent
            button.layer.borderColor = accent.cgColor
            button.setTitleColor(.white, for: .normal)
        } else {
            button.backgroundColor = accentSoft
            button.layer.borderColor = border.cgColor
            button.setTitleColor(text, for: .normal)
        }
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        button.adjustsImageWhenHighlighted = true
    }

    public static func styleToolButton(_ button: UIButton) {
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.backgroundColor = panelSoft
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = border.cgColor
        button.setTitleColor(text, for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 7, left: 11, bottom: 7, right: 11)
    }

    public static func stylePill(_ label: UILabel) {
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.numberOfLines = 1
        label.layer.cornerRadius = 11
        label.layer.masksToBounds = true
        label.textColor = text
        label.backgroundColor = panelSoft
    }
}
