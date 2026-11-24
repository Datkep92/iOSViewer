# AGENTS.md — UltraViewer iOS

## Dự án này là gì

Bản port riêng `iOSViewer` của [MacViewer](https://github.com/DeanOpen/MacViewer) sang iOS 16, viết bằng SwiftPM + UIKit. Phần giao thức giữ gần nguyên vẹn, phần AppKit của macOS được thay bằng giao diện cảm ứng. Đây **không phải** dự án Node `magpie-aws-quick` (dù README có nhắc đến dự án Node đó) và không phải sản phẩm chính thức của UltraViewer.

Luật làm việc chung của mọi dự án nằm ở skill `sep-working-rules`; file này chỉ ghi quy ước riêng của dự án.

## Cấu trúc

- `iOSViewer/Package.swift` — định nghĩa sản phẩm thư viện `iOSViewerKit` và sản phẩm thực thi app `iOSViewerApp`, iOS 16, Swift 5.9+.
- `iOSViewer/Sources/UltraViewerProtocol/` — giao thức từ MacViewer: đăng ký client, tra cứu peer, mã hóa cũ, đóng khung TCP, relay/peer transport, giải mã màn hình, lệnh chuột/phím, từ điển giải mã `8bit.dat`.
- `iOSViewer/Sources/CZstd/`, `iOSViewer/Sources/CG722/` — mã nguồn C kèm license riêng.
- `iOSViewer/Sources/iOSViewerKit/` — hồ sơ đăng ký iOS, điều khiển phiên, ảnh màn hình, giao diện UIKit, scene delegate.
- `iOSViewer/Sources/iOSViewerApp/` — điểm vào `UIApplicationMain`, cấu hình scene, dùng `iOSViewerRootViewController()` làm màn hình gốc.
- `iOSViewer/Sources/iOSViewerScaffold/` — scaffold SwiftPM cũ, chỉ in thông báo, **không** tạo app bundle.
- `iOSViewer/Tests/iOSViewerKitTests/` — test gói.
- `iOSViewer/Scripts/check_ios_viewer.py` — kiểm tra tĩnh, không cần build hay toolchain.
- `iOSViewerApp-Info.plist` — Info.plist của app: bundle id `local.apelin.iOSViewer`, khai báo scene, iOS 16, xoay dọc và ngang hai chiều.
- `.github/workflows/build-ios-app.yml` — workflow GitHub Actions build app trên macOS, đóng gói `.ipa` và upload artifact.
- `README.md`, `iOSViewer/THIRD_PARTY_NOTICES.md` — tài liệu và thông báo bản quyền.

## Kiểm tra tĩnh (chạy được trên iPhone này)

Từ root project:

```sh
python3 iOSViewer/Scripts/check_ios_viewer.py
```

Bộ kiểm tra có thêm needle cho giao diện mới: xoay ngang (`LandscapeLeft`, `LandscapeRight`), toàn màn hình, chổm/phóng to (`UIPinchGestureRecognizer`, `zoomScale`, `zoomIn`, `resetZoom`, `pinchAnchor`, `handleZoomPan`) và nhóm công cụ (`remote-tool-` cùng các hàm gửi lệnh). Ngoài ra kiểm tra theme tối (`ViewerTheme`), icon (khóa `CFBundleIcons` trong plist và lệnh sinh/copy icon trong workflow), thư viện dùng chung (`RemoteControlKit`) và nút «Kết nối lại». Bộ kiểm tra cũng có needle cho ba chế độ chuột (`RemotePointerMode`, `RemoteJoystickView`, `remote-tool-pointer-mode`), lưu máy (`ConnectionStore`, `remote-tool-connections`), giữ kết nối (`UIBackgroundModes`, `prepareForBackground`, `remote-tool-keep-alive`) và nhận kết nối ngược (`ViewerHostController`, `UltraViewerHostSession`, `approvePending`, `declinePending`, `onRequest`, `startIncomingHost`, `showIncomingCredentials`). Chạy lệnh trên để lấy kết quả hiện tại; mốc mới nhất **673/673** sau commit sửa build (`db70a08`), kế đến **668/668** (25/11/2026) sau khi sửa zoom theo điểm chổm và thay luồng xin ID/mật khẩu thật cho kết nối ngược. Mốc **646/646** (25/11/2026) là trước khi sửa hai lỗi đó; **603/603** (24/11/2026) là trước khi thêm chế độ chuột/lưu máy/chuyển ứng dụng; **562/562** (23/11/2026) là trước khi thêm giao diện tối, icon và thư viện dùng chung; **532/532** là mốc cũ hơn nữa.

Bộ kiểm tra cũng chặn: `.macOS(` / `AppKit`, tệp `8bit.dat` nằm trong package, resource `.copy(`/`.process(`, và chuỗi Swift bị cấm. Các needle `wheel(delta:`, `verticalWheel`, `wheelWParam` vẫn được giữ.

## Build và thử

Trên iPhone này **không có toolchain Swift**, nên không chạy được `swift test` hay build tại đây. Dùng một trong hai cách sau:

**GitHub Actions (đã thiết lập):** đẩy lên `main` hoặc chạy tay workflow `.github/workflows/build-ios-app.yml`. Máy macOS có Xcode sẽ chạy kiểm tra tĩnh, build sản phẩm `iOSViewerApp` cho iOS 16, đóng gói `Payload/iOSViewer.app`, ký tạm bằng `codesign --force --sign -` rồi xuất artifact `iOSViewer-packages` gồm hai tệp: `iOSViewer.ipa` (dùng với TrollStore nếu máy đã cài TrollStore) và `iOSViewer.deb` (gói rootless `iphoneos-arm64`, cài bằng Sileo, đặt app tại `/var/jb/Applications/iOSViewer.app`). Cả hai **chưa ký chính thức**; `.deb` chỉ cài được trên iPhone đã jailbreak rootless. Phân phối chính thức cần thêm chứng chỉ và provisioning profile vào workflow.

Khi ghép app bundle, phải chọn tệp thực thi Mach-O (`MH_EXECUTE`) trong `.build`, không lấy tệp đầu tiên trùng tên — tệp dSYM cùng tên sẽ làm TrollStore báo `Unsupported Mach-O type`. Máy build sinh bộ icon app bằng `iOSViewer/Scripts/make_app_icon.py` (vẽ bằng mã, không commit PNG), copy vào app bundle và gói DEB; Info.plist khai báo `CFBundleIcons`. Phiên bản app/gói là `1.2` (build `3`). Workflow hiện lọc bằng `file -b ... | grep 'Mach-O.*executable'`. Lần kiểm chứng gần nhất: run `45243733508` (commit `db70a08`, chạy tay với `include_dictionary=true`) thành công, artifact `iOSViewer-packages-device` gồm `iOSViewer.deb` 1.113.156 byte và `iOSViewer.ipa` 1.499.974 byte; bản 1.2 đã build/install qua Apelin (gói `local.apelin.iosviewer`, installationID `d60070b6-f999-482f-82d8-9e33e21a9f2d`) và mở lại với tiến trình mới, từ điển 112.640 byte băm `9aa457…` đúng. Kiểm tra tĩnh đạt `673/673`. Mốc cũ: bản 1.2 tại commit `0c3adf7` đạt `668/668`; bản 1.1 run `45230106806` (commit `ae5263f`) đạt `603/603`. Để cài trên máy này, script local `apelin/install-device-build.sh` tải artifact đó rồi Apelin build/install; **không** dùng artifact `iOSViewer-packages` thường vì bản đó không có từ điển.

**Máy có Xcode 15+:** dùng trực tiếp sản phẩm `iOSViewerApp` trong `iOSViewer/Package.swift`, hoặc thêm package local `iOSViewer/Package.swift` vào một iOS App target và dùng `iOSViewerRootViewController()` làm root. Scene delegate `iOSViewerSceneDelegate` đã được khai báo trong `iOSViewerApp-Info.plist` và trong mã app.

Bản riêng đã nhúng `8bit.dat` nên không cần chọn tệp trong app; bản sạch bắt người dùng tự cung cấp tệp hợp pháp.

## Giao diện mới (xoay / toàn màn hình / zoom / công cụ / chế độ chuột / lưu máy)

- **Xoay:** app hỗ trợ dọc và ngang trái/phải; xoay máy để xem khung hình rộng hơn.
- **Toàn màn hình:** nút trên thanh công cụ (định danh/thao tác dạng `remote-tool-`) để vào và thoát chế độ toàn màn hình.
- **Zoom:** chổm hai ngón trên khung hình để phóng to/thu nhỏ; nút «Khớp» đặt lại mức zoom. Đã bỏ các nút «zoom + / zoom −» vì chổm là đủ. Khi đã phóng to, kéo/vuốt để xem các vùng ngoài khung; ảnh đi theo hướng ngón tay. Các cử chỉ zoom và kéo không chồng lên lệnh cuộn chuột.
- **Nhóm công cụ điều khiển từ xa:** chat, bảng nhớ tạm, bàn phím, gửi tệp và chấp nhận tệp, âm thanh máy tính, bật/tắt hiển thị con trỏ, chất lượng hình, hình nền, hành động và đổi chiều điều khiển (side switch). Các nút dùng chung tiền tố `remote-tool-`.
- **Ba chế độ điều khiển chuột** (nút «Chế độ» hoặc mục «Chế độ chuột» trong bảng công cụ; lựa chọn được nhớ giữa các lần mở app):
  1. **Chạm trực tiếp:** giữ nguyên cách dùng cũ — chạm ngay vị trí muốn click trên khung hình.
  2. **Bàn rê:** một ngón kéo để di chuyển con trỏ ảo trên máy Windows; chạm để click tại con trỏ. Vòng trắng trên khung hình là vị trí con trỏ ảo (chưa kiểm chứng trên Windows).
  3. **Cần điều khiển:** cần ảo ở góc dưới bên phải; đẩy theo hướng nào thì con trỏ máy Windows đi theo hướng đó, buông tay là dừng. Chế độ này gửi lệnh di chuyển liên tục (~30 lần/giây).
- **Lưu danh sách máy:** mỗi lần kết nối thành công, app lưu ID + mật khẩu phiên vào bộ nhớ riêng của app (tối đa 12 máy). Dropdown «Máy đã lưu ▾» ngay trong khung nhập nhanh cho phép chạm một máy là điền ID/mật khẩu và nối luôn, hoặc xoá danh sách; mục «Danh sách máy đã lưu» trong bảng công cụ vẫn giữ nguyên. **Mật khẩu được lưu dạng rõ trong sandbox** — chỉ dùng cho bản cá nhân trên thiết bị này, không dùng cho bản phân phối chung.
- **Giữ kết nối khi chuyển ứng dụng:** nút «Giữ kết nối» (mặc định Bật). App xin thời gian chạy nền, lưu máy đang dùng và khi quay lại thì tự gọi nối lại nếu phiên trước đó còn hoạt động. iOS vẫn có thể ngừng phiên nền (đặc biệt với `voip` khi không dùng PushKit), nên đây là **tự nối lại khi quay lại app**, không phải cam kết kết nối không bao giờ đứt.

- **Nhận kết nối ngược (Windows → iPhone):** nút «Đổi chiều điều khiển» trong bảng công cụ không còn hỏi ID/mật khẩu do người dùng tự đặt. App mở một phiên nhận (`UltraViewerHostSession`) với đúng hồ sơ đăng ký của thiết bị, lấy ID số và mật khẩu thật do dịch vụ cấp rồi hiện hộp cho người dùng (có nút chép ID và gửi ID sang Windows). Windows nhập ID/mật khẩu đó để gọi ngược lại; khi có yêu cầu, iPhone hiện hộp «Chấp nhận / Từ chối». Màn hình gửi sang Windows là ảnh chụp giao diện app (nền có hoa văn sáng, chụp từ cửa sổ hiện tại); nếu ảnh chụp ra đen — thường khi app đang ở nền — thì gửi ảnh tốt gần nhất hoặc ảnh mẫu, kèm một dòng nhật ký báo lỗi. Chỉ gửi lệnh đổi chiều sau khi đã có ID/mật khẩu thật.

- **Cách dùng cơ bản:** mở app → đợi thông báo sẵn sàng từ điển → kết nối tới máy Windows → chọn chế độ chuột nếu muốn → dùng các nút trên thanh công cụ. Thao tác khung hình giữ nguyên: chạm ngắn = click trái, chạm đôi = click đôi, giữ lâu = click phải, kéo một ngón = diệt chuột, vuốt hai ngón = cuộn dọc/ngang (khi đã zoom thì vuốt để di chuyển khung); thêm chổm hai ngón để zoom.
- Nếu Windows hiện «Chưa có quyền điều khiển…», bấm **Xin quyền** trên thanh công cụ (hoặc «Xin lại quyền điều khiển» trong bảng công cụ) để gửi lại yêu cầu; app không tự bật quyền, Windows vẫn phải chấp nhận.

Đợt gọn giao diện, sửa zoom theo điểm chổm và sửa ảnh đen chiều ngược **mới chỉ có mã, chưa build/cài lại trên máy**: kiểm tra tĩnh vẫn đạt `673/673` và phép toán zoom đã được mô phỏng, nhưng chưa ai thử bằng ngón tay hoặc trên Windows. Bản 1.2 đã cài và khởi động lại nhưng chưa thử các luồng đó trên Windows, nên không ghi nhận là xong.

**CHƯA kiểm chứng trên Windows:** bàn phím, âm thanh máy tính, đổi chiều điều khiển (side switch) và toàn bộ luồng nhận kết nối ngược vừa sửa, truyền tệp (gửi và chấp nhận), phím tắt/hành động, và hai chế độ chuột mới (bàn rê, cần ảo). Việc zoom đúng điểm chổm và kéo khung khi đã phóng to cũng **chưa thử bằng ngón tay trên máy**; mới chỉ mô phỏng phép toán và kiểm tra tĩnh. Checker tĩnh đạt chỉ chứng minh có mã và văn bản giao diện, **không** chứng minh máy Windows nhận và xử lý đúng, cũng không chứng minh app giữ kết nối được khi chuyển ứng dụng thật.

## Giới hạn trên iPhone hiện tại

- Thiết bị **không có toolchain**; CPU thiếu `FEAT_LRCPC`. Không build, không chạy test Swift, không respring hay cài toolchain ở đây.
- Đã cài bản riêng 1.2 lên máy và kiểm tra tệp thực thi, từ điển đúng băm; app mở lại với tiến trình mới (PID thay đổi), không có crash report. Không đọc được cây giao diện lúc Apelin đang mở cùng app, nên chưa xác nhận lại bằng văn bản thông báo sẵn sàng trên bản 1.2. Người dùng xác nhận app báo `Đã sẵn sàng từ điển 8bit.dat.` và **đã kết nối được tới máy Windows**. Khung hình và thao tác chạm đang được kiểm chứng tiếp.
- Điều khiển trên màn hình: chạm ngắn = click trái, chạm đôi = click đôi, giữ lâu = click phải, kéo một ngón = diệt chuột, vuốt hai ngón = cuộn dọc/ngang; khi đã zoom, vuốt để di chuyển khung. Nếu máy Windows để chế độ chỉ xem, app báo rõ và không gửi lệnh. Chưa hỗ trợ kéo thả giữ nút chuột liên tục.
- Cần **người dùng cung cấp `8bit.dat` hợp pháp** (112.640 byte, SHA-256 `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`) cho bản sạch/máy khác. Kho này không chứa, không sao chép và không commit tệp đó hay blob bản quyền nào.
- Nhóm công cụ mới đã xuất hiện trên bản cài 1.1; **chưa thử trên Windows**, nhất là bàn phím, âm thanh, đổi chiều, truyền tệp và phím tắt. Ba chế độ chuột, vòng trỏ ảo trong chế độ bàn rê, cần ảo, danh sách máy đã lưu, tự nối lại sau khi chuyển ứng dụng, luồng xin ID thật cho kết nối ngược và cách zoom theo điểm chổm đã có mã, kiểm tra tĩnh và được đưa vào bản 1.2 đã cài; vẫn chưa ai thử chạy thật trên Windows hoặc bằng ngón tay. Chưa xử lý CAPTCHA/xác thực bổ sung.
- Không dùng AppKit, storyboard hay Theos. Kết nối trực tiếp LAN bị tắt để khỏi xin quyền Local Network.

## Git

Repo công khai: `Datkep92/iOSViewer` (tạo theo yêu cầu của Sếp). Commit thay đổi nội bộ bằng `git_commit(all: true)` sau khi kiểm tra `git status`. Chỉ push khi Sếp yêu cầu; không tạo repo khác, không cài toolchain khi chưa được yêu cầu rõ ràng.
