# CNViewer — UltraViewer trên iPhone (bản port iOS 16)

Tên hiển thị của app là CNViewer; mã nguồn và định danh gói vẫn giữ tên iOSViewer để cài đè bản cũ không mất dữ liệu.

Đây là bản chuyển mã nguồn mở của [MacViewer](https://github.com/DeanOpen/MacViewer) sang iOS 16 bằng SwiftPM và UIKit. Phần giao thức được giữ lại gần như nguyên vẹn; phần macOS (AppKit) được thay bằng màn hình cảm ứng. Đây không phải sản phẩm chính thức của UltraViewer.

Mã port nằm hoàn toàn trong `iOSViewer/`; đây không phải dự án Node `magpie-aws-quick`.

## Cấu trúc

- `iOSViewer/Sources/UltraViewerProtocol/` — đăng ký client, tra cứu peer, mã hóa cũ, đóng khung, relay/peer transport, giải mã màn hình, lệnh từ xa (giữ từ MacViewer).
- `iOSViewer/Sources/CZstd/`, `iOSViewer/Sources/CG722/` — mã nguồn C kèm license riêng.
- `iOSViewer/Sources/iOSViewerKit/` — hồ sơ đăng ký iOS, điều khiển phiên, ảnh màn hình, giao diện UIKit, scene delegate.
- `iOSViewer/Sources/RemoteControlKit/` — thư viện dùng chung: kết nối/tự kết nối lại, xin quyền điều khiển, gộp lệnh chuột/phím. Không phụ thuộc UIKit.
- `iOSViewer/Sources/iOSViewerApp/` — điểm vào app, cấu hình scene, dùng `iOSViewerRootViewController` làm màn hình gốc.
- `iOSViewer/Sources/iOSViewerScaffold/` — scaffold cũ, chỉ in thông báo; không phải app chạy được.
- `iOSViewerApp-Info.plist` — Info.plist của app (bundle id `local.apelin.iOSViewer`, iOS 16, khai báo icon sinh bằng mã).
- `iOSViewer/Scripts/check_ios_viewer.py` — kiểm tra tĩnh, không cần build.
- `iOSViewer/Scripts/make_app_icon.py` — sinh các kích thước icon PNG bằng mã; không lưu ảnh nhị phân trong kho.
- `.github/workflows/build-ios-app.yml` — build app trên macOS bằng GitHub Actions, đóng gói `.ipa`.

## Build app bằng GitHub Actions

Repo công khai `Datkep92/iOSViewer` có workflow `.github/workflows/build-ios-app.yml`. Khi đẩy lên `main` hoặc chạy tay từ tab Actions, workflow dùng máy macOS có Xcode để:

1. chạy kiểm tra tĩnh `python3 iOSViewer/Scripts/check_ios_viewer.py`;
2. build sản phẩm `iOSViewerApp` cho iOS 16;
3. tạo `Payload/iOSViewer.app`, ký tạm bằng `codesign --force --sign -`, nén thành `iOSViewer.ipa` và upload artifact `iOSViewer-unsigned`.

Artifact là app **chưa ký chính thức**: không cài được lên iPhone thường. Muốn phân phối thật cần thêm chứng chỉ, provisioning profile và cấu hình signing trong workflow.

## Dùng trên iPhone

1. Dùng artifact `iOSViewer-unsigned` từ Actions để kiểm tra trên môi trường cho phép app ký tạm, hoặc tự ký lại bằng chứng chỉ của bạn. Trên máy có Xcode 15+, có thể chọn trực tiếp sản phẩm `iOSViewerApp` trong `iOSViewer/Package.swift`, hoặc thêm package local vào một iOS App target và dùng `iOSViewerRootViewController()` làm root; scene delegate đã được khai báo trong Info.plist và trong mã app.
2. **Chuẩn bị từ điển giải mã:** lấy `8bit.dat` từ bản UltraViewer mà bạn có quyền sử dụng, rồi trong app bấm **Chọn từ điển** và chọn tệp đó. Ứng dụng sẽ chép vào `Documents/8bit.dat` của sandbox, kiểm tra đúng 112.640 byte và mã băm `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`. Bạn cũng có thể tự đặt tệp vào `Documents/8bit.dat` qua Files.
3. Nhập ID máy Windows (chuỗi chữ số do UltraViewer hiển thị) và mật khẩu phiên, bấm **Kết nối**. Sau lần kết nối thành công, máy được lưu; lần sau bấm **Máy đã lưu** rồi chọn máy để điền sẵn thông tin. Nút **Giữ kết nối** (mặc định Bật) giúp app tự nối lại khi bạn quay lại sau khi chuyển ứng dụng; iOS vẫn có thể ngừng phiên nền.
4. Chọn **Chế độ** trên thanh công cụ: **Chạm trực tiếp** (chạm đúng vị trí cần click), **Bàn rê** (kéo một ngón để di chuyển con trỏ ảo, chạm để click tại con trỏ — vòng trắng trên khung hình là vị trí con trỏ), hoặc **Cần điều khiển** (đẩy cần ảo ở góc dưới bên phải theo hướng muốn đi). Lựa chọn được nhớ giữa các lần mở app. Chế độ bàn rê và cần ảo chưa được kiểm chứng với máy Windows thật.
5. Khi có khung hình, các cử chỉ chạm, chạm đôi, giữ lâu, kéo một ngón, chổm hai ngón và vuốt hai ngón vẫn dùng như trước; trong chế độ bàn rê/cần điều khiển, kéo một ngón dùng để di chuyển con trỏ thay vì click tại điểm chạm.
6. Bấm **Ngắt** để gửi lệnh kết thúc và đóng phiên.
7. Để Windows điều khiển ngược lại iPhone: mở **Bảng công cụ → Đổi chiều điều khiển**. App sẽ xin ID số và mật khẩu thật từ dịch vụ rồi hiện cho bạn (có nút chép ID và gửi sang Windows). Trên Windows, nhập đúng ID/mật khẩu đó để gọi lại iPhone; khi có yêu cầu, iPhone hiện hộp để bạn chấp nhận hoặc từ chối. Không nhập ID/mật khẩu tự đặt — dịch vụ sẽ không nhận.

Thông tin đăng ký của client (identity/password dùng để đăng ký với dịch vụ) được tạo ngẫu nhiên ngay trên thiết bị và lưu trong Application Support của app. Không có credential nào nằm trong mã nguồn hay tài liệu này.

## Giới hạn

- **Chưa biên dịch, chưa chạy thật trên iPhone này.** Thiết bị không có toolchain, CPU thiếu `FEAT_LRCPC`; việc build/test cần Xcode trên máy tính hoặc GitHub Actions. Kết quả workflow cần được đọc trên tab Actions.
- Bản iOS đã có giao diện cho âm thanh máy tính, bảng nhớ tạm, chat, truyền tệp, đổi chiều điều khiển và các phím tắt; **chưa kiểm chứng trên Windows** nên không coi là đã hoạt động. Vòng trỏ ảo chỉ mới có trong chế độ bàn rê, chưa kiểm chứng với máy Windows. Ba chế độ chuột, cần ảo, danh sách máy đã lưu, tự nối lại sau khi chuyển ứng dụng, luồng xin ID thật cho kết nối ngược và việc zoom đúng điểm chổm mới chỉ có mã, chưa build/cài bản mới để thử thật.
- Danh sách máy đã lưu giữ ID và mật khẩu phiên **dạng rõ** trong bộ nhớ riêng của app (tối đa 12 máy); chỉ dùng cho bản cá nhân, không dùng cho bản phân phối chung.
- Giao diện dùng bảng phối màu tối, có thẻ trạng thái kết nối/quyền điều khiển và nút «Kết nối lại». Icon app được sinh bằng mã lúc build, không lưu ảnh trong kho.
- Kết nối trực tiếp LAN bị tắt để không cần quyền Local Network; kết nối relay vẫn dùng chung mã gốc.
- Cần `8bit.dat` hợp pháp từ người dùng. Kho này **không chứa, không sao chép và không commit** tệp đó hay bất kỳ blob nhị phân bản quyền nào.
- Không dùng AppKit, storyboard hay Theos. `iOSViewerScaffold` chỉ là scaffold; sản phẩm app là `iOSViewerApp`.
- CAPTCHA/xác thực bổ sung từ dịch vụ UltraViewer chưa được xử lý trong UIKit.

## Kiểm tra

Không cần toolchain để chạy:

```sh
python3 iOSViewer/Scripts/check_ios_viewer.py
```

Kết quả gần nhất (sau khi thêm app target và workflow): **ĐẠT: 532/532**, mã thoát 0.

Gói có test target, nhưng `iOSViewerKit` dùng UIKit: chạy `swift test --package-path iOSViewer` trên macOS host thường không được. Workflow hiện chỉ chạy kiểm tra tĩnh và build app cho iOS.

## Giấy phép

Mã MacViewer gốc dùng MIT License, giữ nguyên tại `iOSViewer/MacViewer-LICENSE`. License của Zstandard và G.722 nằm cùng thư mục nguồn C; xem thêm `iOSViewer/THIRD_PARTY_NOTICES.md`. `8bit.dat` là dữ liệu do UltraViewer cung cấp, **không** thuộc MIT License và không được phân phối trong kho này. Dự án chỉ để tương tác cục bộ với máy bạn có quyền điều khiển; hãy tuân thủ điều khoản của dịch vụ UltraViewer.
