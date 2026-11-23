#!/usr/bin/env python3
"""Kiểm tra tĩnh bản port iOSViewer không cần toolchain hay build trên máy.

Phần kiểm tra giao diện mới chỉ xác nhận mã nguồn và Info.plist có các
thành phần: xoay ngang, toàn màn hình, phóng to ảnh và nhóm công cụ điều
khiển. Đây là kiểm tra hiện diện (needle), không chứng minh hành vi chạy
thật trên máy Windows.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
IOS = ROOT / "iOSViewer"
errors: list[str] = []
passed = 0


def check(condition: bool, message: str) -> None:
    global passed
    if condition:
        passed += 1
    else:
        errors.append(message)


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


package_path = IOS / "Package.swift"
package = read(package_path)
check(package_path.is_file(), "Thiếu iOSViewer/Package.swift")
check(".iOS(.v16)" in package, "Package.swift chưa khai báo iOS 16")
check('name: "iOSViewerKit"' in package, "Thiếu sản phẩm thư viện iOSViewerKit")
check(".macOS(" not in package and "AppKit" not in package, "Package.swift còn nhắc tới macOS/AppKit")
check("8bit.dat" not in package, "Package.swift không được khai báo tài nguyên 8bit.dat")
check(".copy(" not in package and ".process(" not in package,
      "Package.swift không được đóng gói tài nguyên nhị phân")

plist_path = ROOT / "iOSViewerApp-Info.plist"
plist = read(plist_path)
check(plist_path.is_file(), "Thiếu iOSViewerApp-Info.plist")
for needle in ("UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"):
    check(needle in plist, f"Info.plist chưa khai báo xoay ngang: {needle}")

files = sorted(p for p in IOS.rglob("*") if p.is_file())
for path in files:
    check(path.suffix.lower() not in {".dat", ".bin", ".zip", ".tar", ".gz", ".tgz", ".deb", ".app", ".framework"},
          f"Không được có tệp nhị phân/bản quyền trong repo: {path.relative_to(ROOT)}")

swift_files = [p for p in files if p.suffix == ".swift"]
for path in swift_files:
    text = read(path)
    check(bool(text), f"Không đọc được tệp Swift: {path.relative_to(ROOT)}")
    for forbidden in ("import AppKit", "NSView", "NSViewController", "%hook", "%orig", "Bundle.module"):
        check(forbidden not in text, f"{path.relative_to(ROOT)} chứa {forbidden}")

protocol_dir = IOS / "Sources" / "UltraViewerProtocol"
protocol_files = sorted(protocol_dir.glob("*.swift"))
check(len(protocol_files) >= 30, f"Chỉ tìm thấy {len(protocol_files)} tệp giao thức Swift")

required = [
    "Sources/UltraViewerProtocol/UltraViewerRelaySession.swift",
    "Sources/UltraViewerProtocol/FramedTCPTransport.swift",
    "Sources/UltraViewerProtocol/LegacyCommandCipher.swift",
    "Sources/UltraViewerProtocol/ModernScreenRenderer.swift",
    "Sources/UltraViewerProtocol/UltraViewerScreenDictionary.swift",
    "Sources/iOSViewerKit/IOSRegistrationProfile.swift",
    "Sources/iOSViewerKit/ViewerSessionController.swift",
    "Sources/iOSViewerKit/RemoteScreenImageView.swift",
    "Sources/iOSViewerKit/iOSViewerRootViewController.swift",
    "Sources/iOSViewerKit/iOSViewerSceneDelegate.swift",
    "Sources/iOSViewerScaffold/main.swift",
    "Tests/iOSViewerKitTests/ViewerKitTests.swift",
    "Scripts/check_ios_viewer.py",
    "MacViewer-LICENSE",
    "THIRD_PARTY_NOTICES.md",
]
for name in required:
    check((IOS / name).is_file(), f"Thiếu tệp: iOSViewer/{name}")

dictionary = read(protocol_dir / "UltraViewerScreenDictionary.swift")
for needle in ("documentDirectory", "expectedByteCount", "expectedSHA256", "public static func use"):
    check(needle in dictionary, f"Dictionary loader thiếu {needle}")

for header in ("Sources/CZstd/include/CZstd.h", "Sources/CG722/include/MacViewerG722.h"):
    check((IOS / header).is_file(), f"Thiếu header nguồn C: {header}")

uikit = read(IOS / "Sources/iOSViewerKit/iOSViewerRootViewController.swift")
# remote-tool- là tiền tố chung cho identifier và action của các nút công cụ.
for needle in ("UIViewController", "UITextField", "UIDocumentPickerViewController", "UITextView",
               "NSLayoutConstraint", "remote-tool-"):
    check(needle in uikit, f"Giao diện UIKit thiếu {needle}")
check("fullscreen" in uikit.lower(), "Giao diện UIKit thiếu chế độ toàn màn hình (fullscreen)")
view = read(IOS / "Sources/iOSViewerKit/RemoteScreenImageView.swift")
for needle in ("UIImageView", "UITapGestureRecognizer", "UILongPressGestureRecognizer", "UIPanGestureRecognizer",
               "wheel(delta:", "horizontalWheel", "remotePoint", "UIPinchGestureRecognizer", "zoomScale",
               "zoomIn", "resetZoom"):
    check(needle in view, f"Chế độ xem màn hình thiếu {needle}")
controller = read(IOS / "Sources/iOSViewerKit/ViewerSessionController.swift")
for needle in ("UltraViewerRelaySession", "frame", "MouseMessage", "sendPointer", "verticalWheel",
               "horizontalWheel", "wheelWParam", "allowsRemoteInput", "applyInputPermission",
               "sendChat", "sendClipboardText", "sendKeyboardText", "sendFile", "acceptLastFileOffer",
               "setComputerAudioEnabled", "setCursorPositionsEnabled", "setQuality", "setWallpaperVisible",
               "sendAction", "requestSideSwitch"):
    check(needle in controller, f"Bộ điều khiển phiên thiếu {needle}")

readme = read(ROOT / "README.md")
for needle in ("iOS 16", "8bit.dat", "MIT", "Chưa"):
    check(needle in readme, f"README root thiếu nội dung bắt buộc: {needle}")

check(not any(p.name == "Resources" and p.is_dir() for p in IOS.rglob("*")),
      "Không được có thư mục Resources chứa tài nguyên bản quyền")

total = passed + len(errors)
if errors:
    print(f"KHÔNG ĐẠT: {len(errors)}/{total} kiểm tra thất bại")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)
print(f"ĐẠT: {passed}/{total} kiểm tra tĩnh")
