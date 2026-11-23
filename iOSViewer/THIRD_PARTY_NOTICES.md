# Thông báo bên thứ ba — bản port iOSViewer

## MacViewer

Mã giao thức trong `Sources/UltraViewerProtocol/` và wrapper C có nguồn từ MacViewer, MIT License, Copyright (c) 2026 MacViewer contributors. Toàn văn giữ tại `MacViewer-LICENSE`.

## Zstandard

`Sources/CZstd/` chứa phần nén/giải nén của Zstandard 1.5.7, copyright Meta Platforms, Inc. and affiliates, theo BSD license; bản GPLv2 thay thế cũng được giữ lại. Xem `Sources/CZstd/LICENSE`, `Sources/CZstd/COPYING` và `Sources/CZstd/provenance.json`. Mã nguồn giữ nguyên; chỉ để phục vụ giải mã/nén khung màn hình.

## G.722

`Sources/CG722/` chứa bộ giải mã G.722 của WebRTC (revision `4fdd50a57b79826ea87cc5170be78b6444d9cdf9`) và wrapper phân bổ bộ nhớ `MacViewerG722.c`. Xem `Sources/CG722/LICENSE` và `Sources/CG722/WEBRTC_LICENSE`. Bản iOS hiện chưa phát âm thanh, nhưng giữ bộ giải mã để tương thích giao thức.

## Dữ liệu 8bit.dat

`8bit.dat` là từ điển Zstandard do UltraViewer cung cấp (112.640 byte, SHA-256 `9aa45789d9ff9d329a623a685d57b67e33c777019de9ce1f273f21860e4bfe6b`, dictionary ID `0x3da0bd10`). Đây không phải mã nguồn mở và không có giấy phép phân phối lại được xác lập. Bản port này **không đính kèm tệp đó**; người dùng tự cung cấp qua trình chọn tệp của ứng dụng vàloader sẽ kiểm tra kích thước/mã băm trước khi dùng.

Không có file thực thi hay thư viện của Windows UltraViewer nào được đóng gói.
