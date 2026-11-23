import UIKit

/// App-scene scaffold for an Xcode iOS app target that links iOSViewerKit.
/// The app target's Info.plist must declare this class in UIApplicationSceneManifest.
public final class iOSViewerSceneDelegate: UIResponder, UIWindowSceneDelegate {
    public var window: UIWindow?

    public func scene(_ scene: UIScene,
                      willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = iOSViewerRootViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}
