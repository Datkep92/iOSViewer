import UIKit
import UniformTypeIdentifiers
import UltraViewerProtocol

/// UIKit screen: enter the Windows ID/password, connect, see the newest
/// frame, rotate or go fullscreen, zoom the frame and drive the desktop from
/// a horizontal tool bar and a tool sheet.
public final class iOSViewerRootViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private enum DocumentPurpose: Equatable {
        case dictionary
        case fileTransfer
    }

    private let controller = ViewerSessionController()
    private let idField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let disconnectButton = UIButton(type: .system)
    private let dictionaryButton = UIButton(type: .system)
    private let toolConnectButton = UIButton(type: .system)
    private let toolDisconnectButton = UIButton(type: .system)
    private let requestControlButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)
    private let zoomInButton = UIButton(type: .system)
    private let zoomOutButton = UIButton(type: .system)
    private let fitButton = UIButton(type: .system)
    private let toolsButton = UIButton(type: .system)
    private let logButton = UIButton(type: .system)
    private let fieldsStack = UIStackView()
    private let actionRow = UIStackView()
    private let contentStack = UIStackView()
    private let toolbarScroll = UIScrollView()
    private let screenContainer = UIView()
    private let screenView = RemoteScreenImageView(frame: .zero)
    private let logView = UITextView()
    private var logLines: [String] = []
    private let timeFormatter = DateFormatter()
    private var documentPurpose: DocumentPurpose = .dictionary
    private var isFullscreen = false
    private var logVisible = true
    private var computerAudioEnabled = false
    private var cursorPositionsEnabled = false
    private var wallpaperVisible = true
    private var aspectConstraint: NSLayoutConstraint?
    private var screenBottomConstraint: NSLayoutConstraint?
    private var screenLeadingConstraint: NSLayoutConstraint?
    private var screenTrailingConstraint: NSLayoutConstraint?

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "iOSViewer"
        view.backgroundColor = .systemBackground
        timeFormatter.timeStyle = .medium
        timeFormatter.dateStyle = .none
        buildLayout()
        applyLayoutMode()
        bindController()
        do {
            _ = try UltraViewerScreenDictionary.load()
            appendLog("Đã sẵn sàng từ điển 8bit.dat.")
        } catch {
            appendLog("Chọn tệp 8bit.dat từ bản UltraViewer hợp pháp, rồi nhập ID máy Windows.")
        }
    }

    // MARK: - Rotation

    public override var shouldAutorotate: Bool { true }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIInterfaceOrientationMask.portrait.union(.landscapeLeft).union(.landscapeRight)
    }

    public override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            // Re-apply the transform so the pan offset is clamped to the new bounds.
            self.screenView.setZoomScale(self.screenView.zoomScale, animated: false)
        }
    }

    // MARK: - Layout

    private func configureButton(_ button: UIButton, title: String,
                                 identifier: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = title
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func buildLayout() {
        idField.placeholder = "ID máy Windows (chỉ chữ số)"
        idField.borderStyle = .roundedRect
        idField.keyboardType = .numberPad
        idField.autocorrectionType = .no
        idField.returnKeyType = .next
        idField.delegate = self
        idField.accessibilityIdentifier = "partner-id"

        passwordField.placeholder = "Mật khẩu phiên"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.accessibilityIdentifier = "session-password"

        connectButton.setTitle("Kết nối", for: .normal)
        connectButton.accessibilityIdentifier = "connect"
        connectButton.accessibilityLabel = "Kết nối"
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        disconnectButton.setTitle("Ngắt", for: .normal)
        disconnectButton.accessibilityIdentifier = "disconnect"
        disconnectButton.accessibilityLabel = "Ngắt"
        disconnectButton.isEnabled = false
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
        dictionaryButton.setTitle("Chọn từ điển", for: .normal)
        dictionaryButton.accessibilityIdentifier = "choose-dictionary"
        dictionaryButton.accessibilityLabel = "Chọn từ điển"
        dictionaryButton.addTarget(self, action: #selector(chooseDictionaryTapped), for: .touchUpInside)

        configureButton(toolConnectButton, title: "Kết nối", identifier: "remote-tool-connect",
                        action: #selector(connectTapped))
        configureButton(toolDisconnectButton, title: "Ngắt", identifier: "remote-tool-disconnect",
                        action: #selector(disconnectTapped))
        toolDisconnectButton.isEnabled = false
        configureButton(requestControlButton, title: "Xin quyền", identifier: "remote-tool-request-control",
                        action: #selector(requestControlTapped))
        configureButton(fullscreenButton, title: "Toàn màn hình", identifier: "remote-tool-fullscreen",
                        action: #selector(fullscreenTapped))
        configureButton(zoomInButton, title: "zoom +", identifier: "remote-tool-zoom-in",
                        action: #selector(zoomInTapped))
        configureButton(zoomOutButton, title: "zoom −", identifier: "remote-tool-zoom-out",
                        action: #selector(zoomOutTapped))
        configureButton(fitButton, title: "Khớp", identifier: "remote-tool-fit", action: #selector(fitTapped))
        configureButton(toolsButton, title: "Công cụ", identifier: "remote-tool-tools", action: #selector(toolsTapped))
        configureButton(logButton, title: "Ẩn nhật ký", identifier: "remote-tool-log", action: #selector(logTapped))

        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .systemFont(ofSize: 12)
        logView.backgroundColor = .secondarySystemBackground
        logView.accessibilityIdentifier = "status-log"
        logView.text = ""

        fieldsStack.axis = .vertical
        fieldsStack.spacing = 8
        fieldsStack.addArrangedSubview(idField)
        fieldsStack.addArrangedSubview(passwordField)

        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.distribution = .fillEqually
        actionRow.addArrangedSubview(connectButton)
        actionRow.addArrangedSubview(disconnectButton)
        actionRow.addArrangedSubview(dictionaryButton)

        let toolButtons = [toolConnectButton, toolDisconnectButton, requestControlButton,
                           fullscreenButton, zoomInButton, zoomOutButton, fitButton, toolsButton, logButton]
        let toolStack = UIStackView(arrangedSubviews: toolButtons)
        toolStack.axis = .horizontal
        toolStack.spacing = 12
        toolStack.alignment = .center
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarScroll.addSubview(toolStack)
        toolbarScroll.translatesAutoresizingMaskIntoConstraints = false
        toolbarScroll.showsHorizontalScrollIndicator = false
        toolbarScroll.accessibilityIdentifier = "remote-tool-bar"

        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(fieldsStack)
        contentStack.addArrangedSubview(actionRow)
        contentStack.addArrangedSubview(toolbarScroll)
        contentStack.addArrangedSubview(logView)

        screenContainer.translatesAutoresizingMaskIntoConstraints = false
        screenContainer.clipsToBounds = true
        screenContainer.backgroundColor = .black
        screenView.translatesAutoresizingMaskIntoConstraints = false
        screenView.accessibilityIdentifier = "remote-screen"
        screenContainer.addSubview(screenView)

        view.addSubview(contentStack)
        view.addSubview(screenContainer)

        let leading = screenContainer.leadingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        let trailing = screenContainer.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        let aspect = screenContainer.heightAnchor.constraint(
            equalTo: screenContainer.widthAnchor, multiplier: 0.5625)
        aspect.priority = .defaultHigh
        let bottom = screenContainer.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        // Ảnh cần đúng tỉ lệ để toàn bộ vùng chạm nằm trên ảnh; khi vào fullscreen
        // constraint tỉ lệ bị tắt và cái này tự động kéo khung kín màn hình.
        bottom.priority = .defaultLow
        screenLeadingConstraint = leading
        screenTrailingConstraint = trailing
        aspectConstraint = aspect
        screenBottomConstraint = bottom

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            leading, trailing, aspect, bottom,
            screenContainer.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 12),
            logView.heightAnchor.constraint(equalToConstant: 110),
            toolStack.topAnchor.constraint(equalTo: toolbarScroll.topAnchor),
            toolStack.bottomAnchor.constraint(equalTo: toolbarScroll.bottomAnchor),
            toolStack.leadingAnchor.constraint(equalTo: toolbarScroll.leadingAnchor),
            toolStack.trailingAnchor.constraint(equalTo: toolbarScroll.trailingAnchor),
            toolStack.heightAnchor.constraint(equalToConstant: 40),
            toolbarScroll.heightAnchor.constraint(equalToConstant: 40),
            screenView.topAnchor.constraint(equalTo: screenContainer.topAnchor),
            screenView.leadingAnchor.constraint(equalTo: screenContainer.leadingAnchor),
            screenView.trailingAnchor.constraint(equalTo: screenContainer.trailingAnchor),
            screenView.bottomAnchor.constraint(equalTo: screenContainer.bottomAnchor)
        ])
    }

    private func applyLayoutMode() {
        fieldsStack.isHidden = isFullscreen
        actionRow.isHidden = isFullscreen
        logView.isHidden = isFullscreen || !logVisible
        toolConnectButton.isHidden = isFullscreen
        toolDisconnectButton.isHidden = isFullscreen
        fullscreenButton.setTitle(isFullscreen ? "Thoát full" : "Toàn màn hình", for: .normal)
        fullscreenButton.accessibilityLabel = isFullscreen ? "Thoát toàn màn hình" : "Toàn màn hình"
        logButton.setTitle(logVisible && !isFullscreen ? "Ẩn nhật ký" : "Hiện nhật ký", for: .normal)
        screenLeadingConstraint?.constant = isFullscreen ? 0 : 16
        screenTrailingConstraint?.constant = isFullscreen ? 0 : -16
        if isFullscreen {
            aspectConstraint?.isActive = false
            screenBottomConstraint?.priority = .required
        } else {
            screenBottomConstraint?.priority = .defaultLow
            aspectConstraint?.isActive = true
        }
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    /// Khung hình luôn ôm đúng ảnh để mọi cử chỉ đều rơi vào ảnh, kể cả máy Windows 4:3.
    private func updateScreenAspect(width: CGFloat, height: CGFloat) {
        guard let old = aspectConstraint, width > 0, height > 0 else { return }
        let ratio = min(max(height / width, 0.35), 2.0)
        guard abs(old.multiplier - ratio) > 0.002 else { return }
        let wasActive = old.isActive
        NSLayoutConstraint.deactivate([old])
        let updated = screenContainer.heightAnchor.constraint(
            equalTo: screenContainer.widthAnchor, multiplier: ratio)
        updated.priority = .defaultHigh
        aspectConstraint = updated
        if wasActive { updated.isActive = true }
    }

    // MARK: - Controller bindings

    private func bindController() {
        controller.onStatus = { [weak self] text in
            self?.appendLog(text)
        }
        controller.onFrame = { [weak self] image, remoteSize in
            guard let self else { return }
            self.screenView.image = UIImage(cgImage: image)
            self.screenView.remoteSize = remoteSize
            if remoteSize.width > 0, remoteSize.height > 0 {
                self.updateScreenAspect(width: remoteSize.width, height: remoteSize.height)
            }
        }
        controller.onState = { [weak self] state in
            guard let self else { return }
            let connected = state != .idle
            self.connectButton.isEnabled = !connected
            self.toolConnectButton.isEnabled = !connected
            self.disconnectButton.isEnabled = connected
            self.toolDisconnectButton.isEnabled = connected
            self.idField.isEnabled = !connected
            self.passwordField.isEnabled = !connected
        }
        screenView.onPointer = { [weak self] kind, point in
            self?.controller.sendPointer(kind, at: point)
        }
    }

    private func appendLog(_ text: String) {
        let line = "[\(timeFormatter.string(from: Date()))] \(text)"
        logLines.append(line)
        if logLines.count > 200 { logLines.removeFirst(logLines.count - 200) }
        logView.text = logLines.joined(separator: "\n")
        let length = logView.text.utf16.count
        if length > 0 {
            logView.scrollRangeToVisible(NSRange(location: length - 1, length: 1))
        }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === idField {
            passwordField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            connectTapped()
        }
        return true
    }

    // MARK: - Tool bar actions

    @objc private func connectTapped() {
        view.endEditing(true)
        let id = idField.text ?? ""
        let password = passwordField.text ?? ""
        Task { await controller.connect(partnerID: id, password: password) }
    }

    @objc private func disconnectTapped() {
        Task { await controller.disconnect() }
    }

    @objc private func requestControlTapped() {
        Task { await controller.requestControlPermission() }
    }

    @objc private func fullscreenTapped() {
        isFullscreen.toggle()
        applyLayoutMode()
    }

    @objc private func zoomInTapped() {
        screenView.zoomIn()
    }

    @objc private func zoomOutTapped() {
        screenView.zoomOut()
    }

    @objc private func fitTapped() {
        screenView.resetZoom()
    }

    @objc private func logTapped() {
        if isFullscreen {
            isFullscreen = false
            logVisible = true
        } else {
            logVisible.toggle()
        }
        applyLayoutMode()
    }

    // MARK: - Tool sheet

    @objc private func toolsTapped() {
        let sheet = UIAlertController(title: "Công cụ điều khiển", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Xin lại quyền điều khiển", style: .default) { [weak self] _ in
            Task { await self?.controller.requestControlPermission() }
        })
        sheet.addAction(UIAlertAction(title: "Chat", style: .default) { [weak self] _ in
            guard let self else { return }
            self.promptText(title: "Chat", placeholder: "Nội dung chat") { text in
                Task { await self.controller.sendChat(text) }
            }
        })
        sheet.addAction(UIAlertAction(title: "Bảng nhớ tạm (gửi text)", style: .default) { [weak self] _ in
            guard let self else { return }
            self.promptText(title: "Bảng nhớ tạm", placeholder: "Nội dung bảng nhớ tạm") { text in
                Task { await self.controller.sendClipboardText(text) }
            }
        })
        sheet.addAction(UIAlertAction(title: "Bàn phím (gửi text)", style: .default) { [weak self] _ in
            guard let self else { return }
            self.promptText(title: "Bàn phím", placeholder: "Ký tự cần gửi") { text in
                Task { await self.controller.sendKeyboardText(text) }
            }
        })
        sheet.addAction(UIAlertAction(title: "Gửi tệp", style: .default) { [weak self] _ in
            self?.presentDocumentPicker(purpose: .fileTransfer)
        })
        let receive = UIAlertAction(title: "Nhận tệp gần nhất", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                self.appendLog("Không tìm thấy thư mục Documents để nhận tệp.")
                return
            }
            Task { await self.controller.acceptLastFileOffer(to: documents) }
        }
        receive.isEnabled = controller.hasPendingFileOffer
        sheet.addAction(receive)

        let audioTitle = computerAudioEnabled ? "Tắt âm thanh máy tính" : "Bật âm thanh máy tính"
        sheet.addAction(UIAlertAction(title: audioTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            let enabled = !self.computerAudioEnabled
            self.computerAudioEnabled = enabled
            Task { await self.controller.setComputerAudioEnabled(enabled) }
        })
        let cursorTitle = cursorPositionsEnabled ? "Ẩn con trỏ từ xa" : "Hiện con trỏ từ xa"
        sheet.addAction(UIAlertAction(title: cursorTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            let enabled = !self.cursorPositionsEnabled
            self.cursorPositionsEnabled = enabled
            Task { await self.controller.setCursorPositionsEnabled(enabled) }
        })

        let presets: [(String, RemoteControlCommands.QualityPreset)] = [
            ("Chất lượng: Nhanh", .speed),
            ("Chất lượng: Đẹp", .quality),
            ("Chất lượng: Tự động", .automatic)
        ]
        for (title, preset) in presets {
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                Task { await self.controller.setQuality(preset) }
            })
        }

        let wallpaperTitle = wallpaperVisible ? "Ẩn hình nền" : "Hiện hình nền"
        sheet.addAction(UIAlertAction(title: wallpaperTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            let visible = !self.wallpaperVisible
            self.wallpaperVisible = visible
            Task { await self.controller.setWallpaperVisible(visible) }
        })

        sheet.addAction(UIAlertAction(title: "Ctrl+Alt+Del", style: .default) { [weak self] _ in
            guard let self else { return }
            Task { await self.controller.sendAction(RemoteControlCommands.Action.controlAltDelete) }
        })
        sheet.addAction(UIAlertAction(title: "Khóa màn hình", style: .default) { [weak self] _ in
            guard let self else { return }
            Task { await self.controller.sendAction(RemoteControlCommands.Action.lockScreen) }
        })
        sheet.addAction(UIAlertAction(title: "Khởi động lại", style: .destructive) { [weak self] _ in
            guard let self else { return }
            let confirm = UIAlertController(title: "Khởi động lại máy Windows?",
                                            message: "Phiên điều khiển sẽ bị ngắt. Bạn có chắc muốn tiếp tục?",
                                            preferredStyle: .alert)
            confirm.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            confirm.addAction(UIAlertAction(title: "Khởi động lại", style: .destructive) { [weak self] _ in
                guard let self else { return }
                Task { await self.controller.sendAction(RemoteControlCommands.Action.restart) }
            })
            presentAfterDismiss(confirm)
        })
        sheet.addAction(UIAlertAction(title: "Đổi chiều điều khiển", style: .default) { [weak self] _ in
            guard let self else { return }
            let alert = UIAlertController(
                title: "Đổi chiều điều khiển",
                message: "ID và mật khẩu nhập ở đây sẽ được gửi tới máy Windows để máy đó kết nối lại vào iPhone. Chỉ thực hiện khi bạn tin tưởng máy đó.",
                preferredStyle: .alert)
            alert.addTextField { field in
                field.placeholder = "ID của bạn (chỉ chữ số)"
                field.keyboardType = .numberPad
            }
            alert.addTextField { field in
                field.placeholder = "Mật khẩu phiên"
                field.isSecureTextEntry = true
            }
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "Gửi", style: .default) { [weak alert, weak self] _ in
                guard let self = self, let fields = alert?.textFields, fields.count >= 2 else { return }
                let ownID = fields[0].text ?? ""
                let password = fields[1].text ?? ""
                Task { await self.controller.requestSideSwitch(ownID: ownID, password: password) }
            })
            presentAfterDismiss(alert)
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))

        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true)
    }

    private func promptText(title: String, placeholder: String,
                            handler: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Gửi", style: .default) { [weak alert] _ in
            guard let text = alert?.textFields?.first?.text, !text.isEmpty else { return }
            handler(text)
        })
        presentAfterDismiss(alert)
    }

    /// Action-sheet handlers can present a second alert while the first is
    /// still on screen; dismissing it first avoids a "already presenting" fail.
    private func presentAfterDismiss(_ controller: UIViewController) {
        if let presented = presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                self?.present(controller, animated: true)
            }
        } else {
            present(controller, animated: true)
        }
    }

    // MARK: - Document picker

    @objc private func chooseDictionaryTapped() {
        presentDocumentPicker(purpose: .dictionary)
    }

    private func presentDocumentPicker(purpose: DocumentPurpose) {
        documentPurpose = purpose
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        if purpose == .dictionary {
            present(picker, animated: true)
        } else {
            presentAfterDismiss(picker)
        }
    }

    public func documentPicker(_ picker: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        switch documentPurpose {
        case .dictionary:
            guard let source = urls.first, let destination = UltraViewerScreenDictionary.defaultFileURL() else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            do {
                let manager = FileManager.default
                try manager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                let data = try Data(contentsOf: source)
                try data.write(to: destination, options: .atomic)
                UltraViewerScreenDictionary.use(destination)
                _ = try UltraViewerScreenDictionary.load()
                appendLog("Đã nạp từ điển 8bit.dat (\(data.count) byte).")
            } catch {
                appendLog("Không nạp được từ điển: \(error.localizedDescription)")
            }
        case .fileTransfer:
            guard let source = urls.first else { return }
            let scoped = source.startAccessingSecurityScopedResource()
            Task { [weak self] in
                guard let self else {
                    if scoped { source.stopAccessingSecurityScopedResource() }
                    return
                }
                await self.controller.sendFile(at: source)
                if scoped { source.stopAccessingSecurityScopedResource() }
                self.appendLog("Đã yêu cầu gửi tệp \(source.lastPathComponent).")
            }
        }
    }

    public func documentPickerWasCancelled(_ picker: UIDocumentPickerViewController) {
        appendLog(documentPurpose == .dictionary ? "Không chọn tệp từ điển." : "Không chọn tệp để gửi.")
    }
}
