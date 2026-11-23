# AGENTS.md — UltraViewer iOS

## Dự án này là gì

Bản port riêng `iOSViewer` của [MacViewer](https://github.com/DeanOpen/MacViewer) sang iOS 16, viết bằng SwiftPM + UIKit. Phần giao thức giữ gần nguyên vẹn, phần AppKit của macOS được thay bằng giao diện cảm ứng. Đây **không phải** dự án Node `magpie-aws-quick` (dù README có nhắc đến dự án Node đó) và không phải sản phẩm chính thức của UltraViewer.

Luật làm việc chung của mọi dự án nằm ở skill `sep-working-rules`; file này chỉ ghi quy ước riêng của dự án.

## Cấu trúc

- `iOSViewer/Package.swift` — định nghĩa sản phẩm thư viện `iOSViewerKit` và sản phẩm thực thi app `iOSViewerApp`, iOS 16, Swift 5.9+.
- `iOSViewer/Sources/UltraViewerProtocol/` — giao thức từ MacViewer: đăng ký client, tra cứu peer, mã hóa cũ, đóng khung TCP, relay/peer transport, giải mã màn hình, lệnh chuột/phím, từ điển giải mã `8bit.dat`.
- `iOSViewer/Sources/CZstd/`, `iOSViewer/Sources/CG722/` — mã nguồn C kèm license riêng.
- `iOSViewer/Sources/iOSViewerKit/` — hồ sơ đăng ký iOS, điều khiển phiên, ảnh màn hình, giao diện UIKit, scene delegate.
- `iOSViewer/Sources/iOSViewerApp/` — điểm vào `UIApplicationMain`, cấu hình scene, dùng `iOSViewerRootViewController` làm màn hình gốc.
- `iOSViewer/Sources/iOSViewerScaffold/` — scaffold SwiftPM cũ, chỉ in thông báo, **không** tạo app bundle.
- `iOSViewer/Tests/iOSViewerKitTests/` — test gói.
- `iOSViewer/Scripts/check_ios_viewer.py` — kiểm tra tĩnh, không cần build hay toolchain.
- `iOSViewerApp-Info.plist` — Info.plist của app: bundle id `local.apelin.iOSViewer`, khai báo scene, iOS 16.
- `.github/workflows/build-ios-app.yml` — workflow GitHub Actions build app trên macOS, đóng gói `.ipa` và upload artifact.
- `README.md`, `iOSViewer/THIRD_PARTY_NOTICES.md` — tài liệu và thông báo bản quyền.

## Kiểm tra tĩnh (chạy được trên iPhone này)

Từ root project:

```sh
python3 iOSViewer/Scripts/check_ios_viewer.py
```

Kết quả lần chạy gần nhất (23/11/2026, sau khi thêm target app và workflow): **ĐẠT: 532/532 kiểm tra tĩnh**, mã thoát 0.

Bộ kiểm tra cũng chặn: `.macOS(` / `AppKit`, tệp `8bit.dat` nằm trong package, resource `.copy(`/`.process(`, và chuỗi Swift bị cấm.

## Build và thử

Trên iPhone này **không có toolchain Swift**, nên không chạy được `swift test` hay build tại đây. Dùng một trong hai cách sau:

**GitHub Actions (đã thiết lập):** đẩy lên `main` hoặc chạy tay workflow `.github/workflows/build-ios-app.yml`. Máy macOS có Xcode sẽ chạy kiểm tra tĩnh, build sản phẩm `iOSViewerApp` cho iOS 16, đóng gói `Payload/iOSViewer.app`, ký tạm bằng `codesign --force --sign -` rồi xuất artifact `iOSViewer-packages` gồm hai tệp: `iOSViewer.ipa` (dùng với TrollStore nếu máy đã cài TrollStore) và `iOSViewer.deb` (gói rootless `iphoneos-arm64`, cài bằng Sileo, đặt app tại `/var/jb/Applications/iOSViewer.app`). Cả hai **chưa ký chính thức**; `.deb` chỉ cài được trên iPhone đã jailbreak rootless. Phân phối chính thức cần thêm chứng chỉ và provisioning profile vào workflow.

Khi ghép app bundle, phải chọn tệp thực thi Mach-O (`MH_EXECUTE`) trong `.build`, không lấy tệp đầu tiên trùng tên — tệp dSYM cùng tên sẽ làm TrollStore báo `Unsupported Mach-O type`. Workflow hiện lọc bằng `file -b ... | grep 'Mach-O.*executable'`. Lần kiểm chứng gần nhất: run `45170827408` (commit `1703195`, chạy tay với `include_dictionary=true`) thành công, artifact `iOSViewer-packages-device` có từ điển riêng. Để cài trên máy này, script local `apelin/install-device-build.sh` tải artifact đó rồi Apelin build/install; **không** dùng artifact `iOSViewer-packages` thường vì bản đó không có từ điển.

**Máy có Xcode 15+:** dùng trực tiếp sản phẩm `iOSViewerApp` trong `iOSViewer/Package.swift`, hoặc thêm package local `iOSViewer/Package.swift` vào một iOS App target và dùng `iOSViewerRootViewController()` làm root. Scene delegate `iOSViewerSceneDelegate` đã được khai báo trong `iOSViewerApp-Info.plist` và trong mã app.

Bản riêng đã nhúng `8bit.dat` nên không cần chọn tệp trong app; bản sạch bắt người dùng tự cung cấp tệp hợp pháp.

## Giới hạn trên iPhone hiện tại

- Thiết bị **không có toolchain**; CPU thiếu `FEAT_LRCPC`. Không build, không chạy test Swift, không respring hay cài toolchain ở đây.
- Đã cài bản riêng mới lên máy và kiểm tra tệp thực thi, từ điển đúng băm. Người dùng xác nhận app báo `Đã sẵn sàng từ điển 8bit.dat.`; lỗi tiếp theo là không ghi được hồ sơ đăng ký, đã sửa ở `IOSRegistrationProfile.swift` nhưng **chưa thử lại sau khi cài bản sửa**. Kết nối thật, khung hình và thao tác chạm vẫn chưa được kiểm chứng.
- Cần **người dùng cung cấp `8bit.dat` hợp pháp** (112.640 byte, SHA-256 `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`) cho bản sạch/máy khác. Kho này không chứa, không sao chép và không commit tệp đó hay blob bản quyền nào.
- Chưa có UIKit cho âm thanh máy tính, bảng nhớ tạm, chat, truyền tệp, đổi chiều điều khiển và lớp vẽ con trỏ; chưa xử lý CAPTCHA/xác thực bổ sung.
- Không dùng AppKit, storyboard hay Theos. Kết nối trực tiếp LAN bị tắt để khỏi xin quyền Local Network.

## Git

Repo công khai: `Datkep92/iOSViewer` (tạo theo yêu cầu của Sếp). Commit thay đổi nội bộ bằng `git_commit(all: true)` sau khi kiểm tra `git status`. Chỉ push khi Sếp yêu cầu; không tạo repo khác, không cài toolchain khi chưa được yêu cầu rõ ràng.
