import UIKit
import UniformTypeIdentifiers
import RemoteControlKit
import UltraViewerProtocol

/// UIKit screen: enter the Windows ID/password, connect, see the newest
/// frame, rotate or go fullscreen, zoom the frame and drive the desktop from
/// a horizontal tool bar and a tool sheet. The visual style comes from
/// ViewerTheme; every accessibility identifier stays stable for existing users.
public final class iOSViewerRootViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private enum DocumentPurpose: Equatable {
        case dictionary
        case fileTransfer
    }

    private let controller = ViewerSessionController()
    private let hostController = ViewerHostController()
    private let idField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let disconnectButton = UIButton(type: .system)
    private let reconnectButton = UIButton(type: .system)
    private let dictionaryButton = UIButton(type: .system)
    private let requestControlButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)
    private let fitButton = UIButton(type: .system)
    private let toolsButton = UIButton(type: .system)
    private let logButton = UIButton(type: .system)
    private let pointerModeButton = UIButton(type: .system)
    private let keepAliveButton = UIButton(type: .system)
    /// Danh sách máy đã lưu dạng dropdown ngay trong thanh nhập nhanh.
    private let savedServersButton = UIButton(type: .system)
    private let joystick = RemoteJoystickView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
    private var pendingCredentials: (id: String, password: String)?
    private var sessionWasActive = false
    private let statusPill = UILabel()
    private let permissionPill = UILabel()
    private let headerStack = UIStackView()
    private let headerTitle = UILabel()
    private let headerSubtitle = UILabel()
    private let connectCard = UIView()
    private let logCard = UIView()
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
    private var lastIncomingCredentials: (id: String, password: String)?
    private var currentState: ViewerSessionController.State = .idle
    private var allowsInput = false
    private var aspectConstraint: NSLayoutConstraint?
    private var screenBottomConstraint: NSLayoutConstraint?
    private var screenLeadingConstraint: NSLayoutConstraint?
    private var screenTrailingConstraint: NSLayoutConstraint?

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "iOSViewer"
        view.backgroundColor = ViewerTheme.background
        timeFormatter.timeStyle = .medium
        timeFormatter.dateStyle = .none
        applyTheme()
        buildLayout()
        applyLayoutMode()
        updateStatusPill()
        updatePermissionPill()
        bindController()
        screenView.mode = ViewerSettings.pointerMode
        joystick.onVector = { [weak self] vector in
            self?.screenView.moveVirtualCursor(by: CGPoint(x: vector.dx * 6, y: vector.dy * 6))
        }
        applyPointerMode()
        applyKeepAliveSetting()
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

    // MARK: - Theme

    private func applyTheme() {
        [connectButton, dictionaryButton].forEach { ViewerTheme.styleButton($0, primary: $0 === connectButton) }
        [disconnectButton, reconnectButton].forEach { ViewerTheme.styleButton($0) }
        [requestControlButton, fullscreenButton, fitButton, toolsButton,
         logButton, pointerModeButton, keepAliveButton].forEach {
            ViewerTheme.styleToolButton($0)
        }
        ViewerTheme.styleToolButton(savedServersButton)
        [idField, passwordField].forEach(ViewerTheme.styleField)
        ViewerTheme.stylePill(statusPill)
        ViewerTheme.stylePill(permissionPill)
        ViewerTheme.styleCard(connectCard)
        ViewerTheme.styleCard(logCard)
        screenContainer.backgroundColor = .black
        screenContainer.layer.cornerRadius = ViewerTheme.radius
        screenContainer.layer.borderWidth = 1
        screenContainer.layer.borderColor = ViewerTheme.border.cgColor
        screenContainer.clipsToBounds = true
        headerTitle.font = .systemFont(ofSize: 22, weight: .bold)
        headerTitle.textColor = ViewerTheme.text
        headerSubtitle.font = .systemFont(ofSize: 12, weight: .medium)
        headerSubtitle.textColor = ViewerTheme.muted
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.textColor = ViewerTheme.text
        logView.backgroundColor = ViewerTheme.panelSoft
        logView.layer.cornerRadius = 12
        logView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
        headerTitle.text = "iOSViewer"
        headerSubtitle.text = "Điều khiển máy Windows từ iPhone"
        statusPill.accessibilityIdentifier = "status-pill"
        permissionPill.accessibilityIdentifier = "permission-pill"

        idField.placeholder = "ID máy Windows (chỉ chữ số)"
        idField.borderStyle = .none
        idField.keyboardType = .numberPad
        idField.autocorrectionType = .no
        idField.returnKeyType = .next
        idField.delegate = self
        idField.accessibilityIdentifier = "partner-id"

        passwordField.placeholder = "Mật khẩu phiên"
        passwordField.borderStyle = .none
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.accessibilityIdentifier = "session-password"

        configureButton(connectButton, title: "Kết nối", identifier: "connect", action: #selector(connectTapped))
        configureButton(disconnectButton, title: "Ngắt", identifier: "disconnect", action: #selector(disconnectTapped))
        configureButton(reconnectButton, title: "Kết nối lại", identifier: "remote-tool-reconnect",
                        action: #selector(reconnectTapped))
        disconnectButton.isEnabled = false
        reconnectButton.isEnabled = false
        configureButton(dictionaryButton, title: "Chọn từ điển", identifier: "choose-dictionary",
                        action: #selector(chooseDictionaryTapped))

        savedServersButton.setTitle("Máy đã lưu ▾", for: .normal)
        savedServersButton.accessibilityIdentifier = "remote-tool-connections"
        savedServersButton.accessibilityLabel = "Danh sách máy đã lưu"
        savedServersButton.showsMenuAsPrimaryAction = true
        savedServersButton.contentHorizontalAlignment = .left
        savedServersButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        refreshSavedServersMenu()

        configureButton(requestControlButton, title: "Xin quyền", identifier: "remote-tool-request-control",
                        action: #selector(requestControlTapped))
        configureButton(fullscreenButton, title: "Toàn màn hình", identifier: "remote-tool-fullscreen",
                        action: #selector(fullscreenTapped))
        configureButton(fitButton, title: "Khớp", identifier: "remote-tool-fit", action: #selector(fitTapped))
        configureButton(toolsButton, title: "Công cụ", identifier: "remote-tool-tools", action: #selector(toolsTapped))
        configureButton(logButton, title: "Ẩn nhật ký", identifier: "remote-tool-log", action: #selector(logTapped))
        configureButton(pointerModeButton, title: "Chế độ: Chạm trực tiếp",
                        identifier: "remote-tool-pointer-mode", action: #selector(pointerModeTapped))
        configureButton(keepAliveButton, title: "Giữ kết nối: Bật",
                        identifier: "remote-tool-keep-alive", action: #selector(keepAliveTapped))

        logView.isEditable = false
        logView.isSelectable = true
        logView.accessibilityIdentifier = "status-log"
        logView.text = ""

        headerStack.axis = .horizontal
        headerStack.spacing = 10
        headerStack.alignment = .center
        let titles = UIStackView(arrangedSubviews: [headerTitle, headerSubtitle])
        titles.axis = .vertical
        titles.spacing = 2
        let pills = UIStackView(arrangedSubviews: [statusPill, permissionPill])
        pills.axis = .vertical
        pills.spacing = 6
        pills.alignment = .fill
        headerStack.addArrangedSubview(titles)
        headerStack.addArrangedSubview(pills)

        fieldsStack.axis = .vertical
        fieldsStack.spacing = 10
        fieldsStack.addArrangedSubview(savedServersButton)
        fieldsStack.addArrangedSubview(idField)
        fieldsStack.addArrangedSubview(passwordField)

        actionRow.axis = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually
        actionRow.addArrangedSubview(connectButton)
        actionRow.addArrangedSubview(disconnectButton)
        actionRow.addArrangedSubview(dictionaryButton)

        let connectInner = UIStackView(arrangedSubviews: [fieldsStack, actionRow])
        connectInner.axis = .vertical
        connectInner.spacing = 12
        connectCard.addSubview(connectInner)
        connectInner.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            connectInner.topAnchor.constraint(equalTo: connectCard.topAnchor, constant: 14),
            connectInner.leadingAnchor.constraint(equalTo: connectCard.leadingAnchor, constant: 14),
            connectInner.trailingAnchor.constraint(equalTo: connectCard.trailingAnchor, constant: -14),
            connectInner.bottomAnchor.constraint(equalTo: connectCard.bottomAnchor, constant: -14),
            idField.heightAnchor.constraint(equalToConstant: 42),
            passwordField.heightAnchor.constraint(equalToConstant: 42),
            savedServersButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        let toolButtons = [reconnectButton, requestControlButton, fullscreenButton,
                           fitButton, toolsButton, logButton, pointerModeButton, keepAliveButton]
        let toolStack = UIStackView(arrangedSubviews: toolButtons)
        toolStack.axis = .horizontal
        toolStack.spacing = 10
        toolStack.alignment = .center
        toolStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarScroll.addSubview(toolStack)
        toolbarScroll.translatesAutoresizingMaskIntoConstraints = false
        toolbarScroll.showsHorizontalScrollIndicator = false
        toolbarScroll.accessibilityIdentifier = "remote-tool-bar"

        logCard.addSubview(logView)
        logView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logView.topAnchor.constraint(equalTo: logCard.topAnchor, constant: 6),
            logView.leadingAnchor.constraint(equalTo: logCard.leadingAnchor, constant: 6),
            logView.trailingAnchor.constraint(equalTo: logCard.trailingAnchor, constant: -6),
            logView.bottomAnchor.constraint(equalTo: logCard.bottomAnchor, constant: -6)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(headerStack)
        contentStack.addArrangedSubview(connectCard)
        contentStack.addArrangedSubview(toolbarScroll)
        contentStack.addArrangedSubview(logCard)

        screenView.translatesAutoresizingMaskIntoConstraints = false
        screenView.accessibilityIdentifier = "remote-screen"
        screenContainer.addSubview(screenView)
        joystick.translatesAutoresizingMaskIntoConstraints = false
        screenContainer.addSubview(joystick)
        screenContainer.translatesAutoresizingMaskIntoConstraints = false

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
            logCard.heightAnchor.constraint(equalToConstant: 122),
            toolStack.topAnchor.constraint(equalTo: toolbarScroll.topAnchor),
            toolStack.bottomAnchor.constraint(equalTo: toolbarScroll.bottomAnchor),
            toolStack.leadingAnchor.constraint(equalTo: toolbarScroll.leadingAnchor),
            toolStack.trailingAnchor.constraint(equalTo: toolbarScroll.trailingAnchor),
            toolStack.heightAnchor.constraint(equalToConstant: 40),
            toolbarScroll.heightAnchor.constraint(equalToConstant: 40),
            screenView.topAnchor.constraint(equalTo: screenContainer.topAnchor),
            screenView.leadingAnchor.constraint(equalTo: screenContainer.leadingAnchor),
            screenView.trailingAnchor.constraint(equalTo: screenContainer.trailingAnchor),
            screenView.bottomAnchor.constraint(equalTo: screenContainer.bottomAnchor),
            joystick.trailingAnchor.constraint(equalTo: screenContainer.trailingAnchor, constant: -12),
            joystick.bottomAnchor.constraint(equalTo: screenContainer.bottomAnchor, constant: -12),
            joystick.widthAnchor.constraint(equalToConstant: 120),
            joystick.heightAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func applyLayoutMode() {
        headerStack.isHidden = isFullscreen
        connectCard.isHidden = isFullscreen
        logCard.isHidden = isFullscreen || !logVisible
        reconnectButton.isHidden = isFullscreen
        keepAliveButton.isHidden = isFullscreen
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
            self.currentState = state
            self.updateStatusPill()
            let active = state == .connected
            let busy = state != .idle
            self.connectButton.isEnabled = !busy
            self.disconnectButton.isEnabled = busy
            self.reconnectButton.isEnabled = state != .idle
            self.idField.isEnabled = !busy
            self.passwordField.isEnabled = !busy
            if state == .connected, let credentials = self.pendingCredentials {
                ConnectionStore.save(partnerID: credentials.id, password: credentials.password)
                self.appendLog("Đã lưu máy \(credentials.id) vào danh sách kết nối.")
                self.refreshSavedServersMenu()
                self.pendingCredentials = nil
            }
        }
        controller.onPermission = { [weak self] allowed in
            guard let self else { return }
            self.allowsInput = allowed
            self.updatePermissionPill()
        }
        screenView.onPointer = { [weak self] kind, point in
            self?.controller.sendPointer(kind, at: point)
        }
        hostController.onStatus = { [weak self] text in
            self?.appendLog(text)
        }
        hostController.onRequest = { [weak self] viewerID in
            self?.showIncomingRequest(viewerID: viewerID)
        }
        hostController.onRegistered = { [weak self] id, password in
            guard id != self?.lastIncomingCredentials?.id ||
                    password != self?.lastIncomingCredentials?.password else { return }
            self?.showIncomingCredentials(id: id, password: password)
        }
        hostController.onConnected = { [weak self] viewerID in
            self?.appendLog("Windows \(viewerID) đã kết nối vào iPhone.")
        }
        hostController.frameProvider = { [weak self] in
            guard let self else { return ViewerHostController.placeholderFrame() }
            let target = self.view.window ?? self.view
            return ViewerHostController.frame(from: target)
        }
    }

    private func updateStatusPill() {
        let text: String
        let color: UIColor
        switch currentState {
        case .idle:
            text = "CHƯA KẾT NỐI"
            color = ViewerTheme.muted
        case .connecting:
            text = "ĐANG KẾT NỐI"
            color = ViewerTheme.warning
        case .connected:
            text = "ĐÃ KẾT NỐI"
            color = ViewerTheme.success
        }
        statusPill.text = "  \(text)  "
        statusPill.backgroundColor = color.withAlphaComponent(0.18)
        statusPill.textColor = color
    }

    private func updatePermissionPill() {
        let text = allowsInput ? "ĐANG ĐIỀU KHIỂN" : "CHỈ XEM"
        let color = allowsInput ? ViewerTheme.accent : ViewerTheme.warning
        permissionPill.text = "  \(text)  "
        permissionPill.backgroundColor = color.withAlphaComponent(0.18)
        permissionPill.textColor = color
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
        pendingCredentials = (id: id, password: password)
        Task { await controller.connect(partnerID: id, password: password) }
    }

    @objc private func disconnectTapped() {
        Task {
            await controller.disconnect()
            await hostController.stop()
        }
    }

    @objc private func reconnectTapped() {
        Task { await controller.reconnect() }
    }

    @objc private func requestControlTapped() {
        Task { await controller.requestControlPermission() }
    }

    @objc private func fullscreenTapped() {
        isFullscreen.toggle()
        applyLayoutMode()
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

    @objc private func pointerModeTapped() {
        let sheet = UIAlertController(title: "Chế độ điều khiển chuột", message: nil, preferredStyle: .actionSheet)
        for mode in RemotePointerMode.allCases {
            let title = mode == screenView.mode ? "✓ \(mode.title)" : mode.title
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                ViewerSettings.pointerMode = mode
                self.applyPointerMode()
                self.appendLog("Chế độ chuột: \(mode.title).")
            })
        }
        sheet.addAction(UIAlertAction(title: "Xong", style: .cancel))
        sheet.popoverPresentationController?.sourceView = pointerModeButton
        presentAfterDismiss(sheet)
    }

    private func applyPointerMode() {
        let mode = ViewerSettings.pointerMode
        screenView.mode = mode
        joystick.isHidden = mode != .joystick
        let title = "Chế độ: \(mode.title)"
        pointerModeButton.setTitle(title, for: .normal)
        pointerModeButton.accessibilityLabel = title
    }

    /// Dropdown ngay thanh nhập: chạm một máy là điền thông tin và kết nối luôn.
    private func refreshSavedServersMenu() {
        let items = ConnectionStore.all()
        var actions: [UIAction] = []
        for item in items.prefix(8) {
            actions.append(UIAction(title: "\(item.label) · \(item.partnerID)") { [weak self] _ in
                guard let self else { return }
                self.idField.text = item.partnerID
                self.passwordField.text = item.password
                self.connectTapped()
            })
        }
        if actions.isEmpty {
            actions.append(UIAction(title: "Chưa có máy nào — hãy kết nối một lần",
                                    attributes: .disabled) { _ in })
        } else {
            actions.append(UIAction(title: "Xoá danh sách máy", attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                ConnectionStore.clear()
                self.appendLog("Đã xoá danh sách máy đã lưu.")
                self.refreshSavedServersMenu()
            })
        }
        savedServersButton.menu = UIMenu(children: actions)
        let count = items.count
        savedServersButton.setTitle(count == 0 ? "Máy đã lưu ▾" : "Máy đã lưu (\(count)) ▾",
                                    for: .normal)
    }

    @objc private func connectionsTapped() {
        let items = ConnectionStore.all()
        let sheet = UIAlertController(title: "Máy đã lưu",
                                      message: items.isEmpty ? "Chưa có máy nào. Kết nối một lần để máy được lưu lại."
                                                            : "Chạm một máy để điền thông tin và kết nối.",
                                      preferredStyle: .actionSheet)
        for item in items.prefix(8) {
            sheet.addAction(UIAlertAction(title: "\(item.label) · \(item.partnerID)", style: .default) { [weak self] _ in
                guard let self else { return }
                self.idField.text = item.partnerID
                self.passwordField.text = item.password
                self.connectTapped()
            })
        }
        if !items.isEmpty {
            sheet.addAction(UIAlertAction(title: "Xoá danh sách máy", style: .destructive) { [weak self] _ in
                guard let self else { return }
                ConnectionStore.clear()
                self.appendLog("Đã xoá danh sách máy đã lưu.")
            })
        }
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        sheet.popoverPresentationController?.sourceView = savedServersButton
        presentAfterDismiss(sheet)
    }

    @objc private func keepAliveTapped() {
        let enabled = !ViewerSettings.keepConnectionInBackground
        ViewerSettings.keepConnectionInBackground = enabled
        applyKeepAliveSetting()
        appendLog(enabled ? "Giữ kết nối khi chuyển ứng dụng: Bật."
                          : "Giữ kết nối khi chuyển ứng dụng: Tắt.")
    }

    private func applyKeepAliveSetting() {
        let enabled = ViewerSettings.keepConnectionInBackground
        let state = enabled ? "Bật" : "Tắt"
        let title = "Giữ kết nối: \(state)"
        keepAliveButton.setTitle(title, for: .normal)
        keepAliveButton.accessibilityLabel = title
    }

    // MARK: - Tool sheet

    @objc private func toolsTapped() {
        let sheet = UIAlertController(title: "Công cụ điều khiển", message: nil, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Kết nối lại", style: .default) { [weak self] _ in
            Task { await self?.controller.reconnect() }
        })
        sheet.addAction(UIAlertAction(title: "Chế độ chuột", style: .default) { [weak self] _ in
            self?.pointerModeTapped()
        })
        sheet.addAction(UIAlertAction(title: "Danh sách máy đã lưu", style: .default) { [weak self] _ in
            self?.connectionsTapped()
        })
        let keepTitle = ViewerSettings.keepConnectionInBackground
            ? "Tắt giữ kết nối khi chuyển app" : "Bật giữ kết nối khi chuyển app"
        sheet.addAction(UIAlertAction(title: keepTitle, style: .default) { [weak self] _ in
            self?.keepAliveTapped()
        })
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
            if let credentials = self.lastIncomingCredentials, self.hostController.isRunning {
                self.showIncomingCredentials(id: credentials.id, password: credentials.password)
                return
            }
            let alert = UIAlertController(
                title: "Đổi chiều điều khiển",
                message: "iPhone sẽ xin một ID số riêng rồi chờ Windows nhập ID đó để kết nối ngược vào máy này. ID và mật khẩu sẽ hiện trên màn hình sau vài giây.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
            alert.addAction(UIAlertAction(title: "Bắt đầu", style: .default) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in await self.startIncomingHost() }
            })
            presentAfterDismiss(alert)
        })
        sheet.addAction(UIAlertAction(title: "Hủy", style: .cancel))

        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = view.bounds
        present(sheet, animated: true)
    }

    private func showIncomingRequest(viewerID: String) {
        let alert = UIAlertController(
            title: "Windows xin kết nối",
            message: "Máy \(viewerID) muốn xem màn hình và điều khiển iPhone. Chỉ chấp nhận nếu đó là máy bạn tin tưởng.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Từ chối", style: .cancel) { [weak self] _ in
            Task { await self?.hostController.declinePending() }
        })
        alert.addAction(UIAlertAction(title: "Chấp nhận", style: .default) { [weak self] _ in
            Task { await self?.hostController.approvePending() }
        })
        presentAfterDismiss(alert)
    }

    private func startIncomingHost() async {
        do {
            try await hostController.start()
            appendLog("Đang xin ID số cho iPhone từ máy chủ UltraViewer…")
        } catch {
            appendLog("Không mở được chế độ nhận kết nối: \(error.localizedDescription)")
        }
    }

    private func showIncomingCredentials(id: String, password: String) {
        lastIncomingCredentials = (id: id, password: password)
        let alert = UIAlertController(
            title: "iPhone đã có ID kết nối",
            message: "Trên Windows, chọn kết nối theo ID rồi nhập đúng ID và mật khẩu bên dưới. Khi Windows gửi yêu cầu, iPhone sẽ hiện hộp để bạn xác nhận.",
            preferredStyle: .alert)
        alert.addTextField { field in
            field.text = id
            field.isEnabled = false
        }
        alert.addTextField { field in
            field.text = password
            field.isEnabled = false
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Chép ID", style: .default) { _ in
            UIPasteboard.general.string = id
        })
        alert.addAction(UIAlertAction(title: "Gửi ID sang Windows", style: .default) { [weak self] _ in
            guard let self else { return }
            Task { await self.controller.requestSideSwitch(ownID: id, password: password) }
            self.appendLog("Đã gửi ID \(id) sang Windows để đổi chiều.")
        })
        alert.addAction(UIAlertAction(title: "Đã ghi", style: .cancel))
        presentAfterDismiss(alert)
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
    /// still on screen; dismissing it first avoids an "already presenting" fail.
    private func presentAfterDismiss(_ controller: UIViewController) {
        if let presented = presentedViewController {
            presented.dismiss(animated: true) { [weak self] in
                self?.present(controller, animated: true)
            }
        } else {
            present(controller, animated: true)
        }
    }

    // MARK: - App lifecycle

    /// Gọi khi app đi vào nền: lưu máy đang dùng và xin thêm thời gian ở scene delegate.
    public func prepareForBackground() {
        guard ViewerSettings.keepConnectionInBackground else { return }
        sessionWasActive = currentState != .idle
        if currentState == .connected, let id = idField.text, !id.isEmpty {
            ConnectionStore.save(partnerID: id, password: passwordField.text ?? "")
        } else if let credentials = pendingCredentials {
            ConnectionStore.save(partnerID: credentials.id, password: credentials.password)
        }
        appendLog("Chuyển ứng dụng: đang giữ phiên điều khiển.")
    }

    /// iOS có thể ngừng phiên nền; quay lại app thì nối lại nếu trước đó đang kết nối.
    public func resumeAfterBackground() {
        guard ViewerSettings.keepConnectionInBackground, sessionWasActive else { return }
        sessionWasActive = false
        guard currentState != .connected, currentState != .connecting else { return }
        appendLog("Quay lại app: đang nối lại phiên điều khiển.")
        Task { [weak self] in
            await self?.controller.reconnect()
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
