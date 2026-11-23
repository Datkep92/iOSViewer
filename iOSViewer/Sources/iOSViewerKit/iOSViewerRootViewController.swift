import UIKit
import UniformTypeIdentifiers
import UltraViewerProtocol

/// Minimal UIKit screen: enter the Windows ID/password, connect, see the newest
/// frame, tap to send mouse commands, and read status/log lines.
public final class iOSViewerRootViewController: UIViewController, UITextFieldDelegate, UIDocumentPickerDelegate {
    private let controller = ViewerSessionController()
    private let idField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let disconnectButton = UIButton(type: .system)
    private let dictionaryButton = UIButton(type: .system)
    private let screenView = RemoteScreenImageView(frame: .zero)
    private let logView = UITextView()
    private var logLines: [String] = []
    private let timeFormatter = DateFormatter()

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "iOSViewer"
        view.backgroundColor = .systemBackground
        timeFormatter.timeStyle = .medium
        timeFormatter.dateStyle = .none
        buildLayout()
        bindController()
        appendLog("Chọn tệp 8bit.dat từ bản UltraViewer hợp pháp, rồi nhập ID máy Windows.")
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
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        disconnectButton.setTitle("Ngắt", for: .normal)
        disconnectButton.accessibilityIdentifier = "disconnect"
        disconnectButton.isEnabled = false
        disconnectButton.addTarget(self, action: #selector(disconnectTapped), for: .touchUpInside)
        dictionaryButton.setTitle("Chọn từ điển", for: .normal)
        dictionaryButton.accessibilityIdentifier = "choose-dictionary"
        dictionaryButton.addTarget(self, action: #selector(chooseDictionaryTapped), for: .touchUpInside)

        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .systemFont(ofSize: 12)
        logView.backgroundColor = .secondarySystemBackground
        logView.accessibilityIdentifier = "status-log"
        logView.text = ""

        let fields = UIStackView(arrangedSubviews: [idField, passwordField])
        fields.axis = .vertical
        fields.spacing = 8
        let buttons = UIStackView(arrangedSubviews: [connectButton, disconnectButton, dictionaryButton])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually

        let root = UIStackView(arrangedSubviews: [fields, buttons, screenView, logView])
        root.axis = .vertical
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            screenView.heightAnchor.constraint(equalTo: screenView.widthAnchor, multiplier: 0.62),
            logView.heightAnchor.constraint(equalToConstant: 130)
        ])
    }

    private func bindController() {
        controller.onStatus = { [weak self] text in
            self?.appendLog(text)
        }
        controller.onFrame = { [weak self] image, remoteSize in
            guard let self else { return }
            self.screenView.image = UIImage(cgImage: image)
            self.screenView.remoteSize = remoteSize
        }
        controller.onState = { [weak self] state in
            guard let self else { return }
            let connected = state != .idle
            self.connectButton.isEnabled = !connected
            self.disconnectButton.isEnabled = connected
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

    @objc private func connectTapped() {
        view.endEditing(true)
        let id = idField.text ?? ""
        let password = passwordField.text ?? ""
        Task { await controller.connect(partnerID: id, password: password) }
    }

    @objc private func disconnectTapped() {
        Task { await controller.disconnect() }
    }

    @objc private func chooseDictionaryTapped() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    public func documentPicker(_ picker: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
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
    }

    public func documentPickerWasCancelled(_ picker: UIDocumentPickerViewController) {
        appendLog("Không chọn tệp từ điển.")
    }
}
