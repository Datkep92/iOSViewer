import UIKit
import UltraViewerProtocol

/// App-scene scaffold for an Xcode iOS app target that links iOSViewerKit.
/// The app target's Info.plist must declare this class in UIApplicationSceneManifest.
public final class iOSViewerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    public func scene(_ scene: UIScene,
                      willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        UltraViewerScreenDictionary.installBundledDictionaryIfNeeded()
        let window = UIWindow(windowScene: scene)
        window.rootViewController = iOSViewerRootViewController()
        self.window = window
        window.makeKeyAndVisible()
    }

    /// iOS chỉ cho phép giữ phiên thêm một khoảng ngắn. Khi hết hạn, app tự
    /// nối lại ở sceneWillEnterForeground thay vì giả vờ kết nối vẫn còn.
    public func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? iOSViewerRootViewController)?.prepareForBackground()
        guard ViewerSettings.keepConnectionInBackground, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "iOSViewerRemoteSession") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    public func sceneWillEnterForeground(_ scene: UIScene) {
        endBackgroundTask()
        (window?.rootViewController as? iOSViewerRootViewController)?.resumeAfterBackground()
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
