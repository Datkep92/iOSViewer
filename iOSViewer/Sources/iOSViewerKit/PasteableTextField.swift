import UIKit

/// Ô nhập cho phép Dán/Sao chép kể cả khi che nội dung (mật khẩu) hoặc dùng
/// bàn phím số (ID máy). iOS ẩn các mục này trong menu chỉnh sửa mặc định,
/// nên lớp này bật lại để người dùng vẫn có thể dán bằng menu giữ lâu.
public final class PasteableTextField: UITextField {
    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(UIResponderStandardEditActions.paste(_:)),
             #selector(UIResponderStandardEditActions.copy(_:)),
             #selector(UIResponderStandardEditActions.cut(_:)),
             #selector(UIResponderStandardEditActions.select(_:)),
             #selector(UIResponderStandardEditActions.selectAll(_:)):
            return true
        default:
            return super.canPerformAction(action, withSender: sender)
        }
    }
}
