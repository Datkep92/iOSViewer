# iOSViewer — UltraViewer trên iPhone (bản port iOS 16)

Đây là bản chuyển mã nguồn mở của [MacViewer](https://github.com/DeanOpen/MacViewer) sang iOS 16 bằng SwiftPM và UIKit. Phần giao thức được giữ lại gần như nguyên vẹn; phần macOS (AppKit) được thay bằng màn hình cảm ứng. Đây không phải sản phẩm chính thức của UltraViewer.

Workspace này vẫn giữ dự án Node cũ `magpie-aws-quick`; README cũ được lưu ở `README.magpie-aws-quick.md`. Mã port nằm hoàn toàn trong `iOSViewer/`.

## Cấu trúc

- `iOSViewer/Sources/UltraViewerProtocol/` — đăng ký client, tra cứu peer, mã hóa cũ, đóng khung, relay/peer transport, giải mã màn hình, lệnh từ xa (giữ từ MacViewer).
- `iOSViewer/Sources/CZstd/`, `iOSViewer/Sources/CG722/` — mã nguồn C kèm license riêng.
- `iOSViewer/Sources/iOSViewerKit/` — hồ sơ đăng ký iOS, điều khiển phiên, ảnh màn hình, giao diện UIKit, scene delegate.
- `iOSViewer/Sources/iOSViewerScaffold/` — scaffold cho SwiftPM; không phải app chạy được ngay.
- `iOSViewer/Scripts/check_ios_viewer.py` — kiểm tra tĩnh, không cần build.

## Dùng trên iPhone

1. Trên máy có Xcode 15+, tạo một iOS App target (iOS 16+), thêm package local `iOSViewer/Package.swift` và link `iOSViewerKit`.
2. Trong `Info.plist` của app target, khai báo `iOSViewerSceneDelegate` trong `UIApplicationSceneManifest`. Nếu không dùng scene delegate, hãy gán `iOSViewerRootViewController()` làm `rootViewController` của window.
3. **Chuẩn bị từ điển giải mã:** lấy `8bit.dat` từ bản UltraViewer mà bạn có quyền sử dụng, rồi trong app bấm **Chọn từ điển** và chọn tệp đó. Ứng dụng sẽ chép vào `Documents/8bit.dat` của sandbox, kiểm tra đúng 112.640 byte và mã băm `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`. Bạn cũng có thể tự đặt tệp vào `Documents/8bit.dat` qua Files.
4. Nhập ID máy Windows (chuỗi chữ số do UltraViewer hiển thị) và mật khẩu phiên, bấm **Kết nối**.
5. Khi có khung hình, chạm một lần = click chuột trái; chạm hai lần = double click; nhấn giữ = click chuột phải. Mỗi thao tác gửi lệnh di chuyển rồi lệnh nút chuột tới máy Windows.
6. Bấm **Ngắt** để gửi lệnh kết thúc và đóng phiên.

Thông tin đăng ký của client (identity/password dùng để đăng ký với dịch vụ) được tạo ngẫu nhiên ngay trên thiết bị và lưu trong Application Support của app. Không có credential nào nằm trong mã nguồn hay tài liệu này.

## Giới hạn

- **Chưa biên dịch, chưa chạy thật trên iPhone này.** Thiết bị không có toolchain, CPU thiếu `FEAT_LRCPC`; việc build/test cần Xcode trên máy tính hoặc môi trường hỗ trợ Swift 5.9+.
- Bản iOS chưa có giao diện cho âm thanh máy tính, bảng nhớ tạm, chat, truyền tệp, đổi chiều điều khiển hay lớp vẽ con trỏ; các sự kiện đó chỉ được ghi vào log.
- Kết nối trực tiếp LAN bị tắt để không cần quyền Local Network; kết nối relay vẫn dùng chung mã gốc.
- Cần `8bit.dat` hợp pháp từ người dùng. Kho này **không chứa, không sao chép và không commit** tệp đó hay bất kỳ blob nhị phân bản quyền nào.
- Không dùng AppKit, storyboard hay Theos. `iOSViewerScaffold` chỉ là scaffold cho SwiftPM; SwiftPM không tạo app bundle iOS được chạy thẳng trên máy.
- CAPTCHA/xác thực bổ sung từ dịch vụ UltraViewer chưa được xử lý trong UIKit.

## Kiểm tra

Không cần toolchain để chạy:

```sh
python3 iOSViewer/Scripts/check_ios_viewer.py
```

Trên máy có Xcode/Swift:

```sh
swift test --package-path iOSViewer
```

## Giấy phép

Mã MacViewer gốc dùng MIT License, giữ nguyên tại `iOSViewer/MacViewer-LICENSE`. License của Zstandard và G.722 nằm cùng thư mục nguồn C; xem thêm `iOSViewer/THIRD_PARTY_NOTICES.md`. `8bit.dat` là dữ liệu do UltraViewer cung cấp, **không** thuộc MIT License và không được phân phối trong kho này. Dự án chỉ để tương tác cục bộ với máy bạn có quyền điều khiển; hãy tuân thủ điều khoản của dịch vụ UltraViewer.
