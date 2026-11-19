import UIKit
#if canImport(DramaPlayer)
import DramaPlayer
#else
import ReelsPlaybackCore
#endif

enum DemoLogging {
    static var logger: PlaybackLogger? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "DramaPlayerDebugLogging") {
            return .system(subsystem: "com.amiaocat.DramaPlayerDemo", minimumLevel: .debug)
        }
        #endif
        return nil
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController(rootViewController: DemoMenuViewController())
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = DemoStyle.canvas
        appearance.shadowColor = .clear
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        navigation.navigationBar.tintColor = DemoStyle.accent
        navigation.navigationBar.prefersLargeTitles = false
        window.rootViewController = navigation
        window.overrideUserInterfaceStyle = .dark
        self.window = window
        window.makeKeyAndVisible()
    }
}
