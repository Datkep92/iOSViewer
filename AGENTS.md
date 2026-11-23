# AGENTS.md — UltraViewer iOS

## Dự án này là gì

Bản port riêng `iOSViewer` của [MacViewer](https://github.com/DeanOpen/MacViewer) sang iOS 16, viết bằng SwiftPM + UIKit. Phần giao thức giữ gần nguyên vẹn, phần AppKit của macOS được thay bằng giao diện cảm ứng. Đây **không phải** dự án Node `magpie-aws-quick` (dù README có nhắc đến dự án Node đó) và không phải sản phẩm chính thức của UltraViewer.

Luật làm việc chung của mọi dự án nằm ở skill `sep-working-rules`; file này chỉ ghi quy ước riêng của dự án.

## Cấu trúc

- `iOSViewer/Package.swift` — định nghĩa sản phẩm thư viện `iOSViewerKit`, iOS 16, Swift 5.9+.
- `iOSViewer/Sources/UltraViewerProtocol/` — giao thức từ MacViewer: đăng ký client, tra cứu peer, mã hóa cũ, đóng khung TCP, relay/peer transport, giải mã màn hình, lệnh chuột/phím, từ điển giải mã `8bit.dat`.
- `iOSViewer/Sources/CZstd/`, `iOSViewer/Sources/CG722/` — mã nguồn C kèm license riêng.
- `iOSViewer/Sources/iOSViewerKit/` — hồ sơ đăng ký iOS, điều khiển phiên, ảnh màn hình, giao diện UIKit, scene delegate.
- `iOSViewer/Sources/iOSViewerScaffold/` — scaffold cho SwiftPM, chưa phải app bundle chạy được ngay.
- `iOSViewer/Tests/iOSViewerKitTests/` — test gói.
- `iOSViewer/Scripts/check_ios_viewer.py` — kiểm tra tĩnh, không cần build hay toolchain.
- `README.md`, `iOSViewer/THIRD_PARTY_NOTICES.md` — tài liệu và thông báo bản quyền.

## Kiểm tra tĩnh (chạy được trên iPhone này)

Từ root project:

```sh
python3 iOSViewer/Scripts/check_ios_viewer.py
```

Kết quả lần chạy gần nhất (23/11/2026): **ĐẠT: 524/524 kiểm tra tĩnh**, mã thoát 0.

## Build và thử (cần máy có Xcode, Swift 5.9+)

```sh
swift test --package-path iOSViewer
```

SwiftPM chỉ tạo thư viện và chạy test; để có app chạy được, trên máy có Xcode 15+ tạo iOS App target (iOS 16+), thêm package local `iOSViewer/Package.swift`, link `iOSViewerKit`, rồi khai báo `iOSViewerSceneDelegate` trong `UIApplicationSceneManifest` (hoặc gán `iOSViewerRootViewController()` làm root của window). Trước khi kết nối phải chọn tệp `8bit.dat` trong app.

## Giới hạn trên iPhone hiện tại

- Thiết bị **không có toolchain**; CPU thiếu `FEAT_LRCPC`. Không build, không chạy test Swift, không respring hay cài toolchain ở đây.
- **Chưa biên dịch, chưa chạy thật** trên iPhone này: mọi kết nối, hiển thị khung hình và thao tác chạm chưa được kiểm chứng bằng thiết bị; mới chỉ có kết quả kiểm tra tĩnh.
- Cần **người dùng cung cấp `8bit.dat` hợp pháp** (112.640 byte, SHA-256 `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`). Kho này không chứa, không sao chép và không commit tệp đó hay blob bản quyền nào.
- Chưa có UIKit cho âm thanh máy tính, bảng nhớ tạm, chat, truyền tệp, đổi chiều điều khiển và lớp vẽ con trỏ; chưa xử lý CAPTCHA/xác thực bổ sung.
- Không dùng AppKit, storyboard hay Theos. Kết nối trực tiếp LAN bị tắt để khỏi xin quyền Local Network.

## Git

Commit thay đổi nội bộ bằng `git_commit(all: true)` sau khi kiểm tra `git status`. **Không push, không tạo repo GitHub, không cài toolchain** khi chưa được người dùng yêu cầu rõ ràng.
