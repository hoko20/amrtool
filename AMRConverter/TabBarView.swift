import SwiftUI
import UIKit

/// 按 SandboxExplorer 的 SceneDelegate 逻辑搭建的 Tab 栏：
/// UITabBarController + 每个 Tab 一个 UINavigationController（大标题）+ 系统 SF Symbol。
/// Tab 栏使用不透明外观，不使用液态玻璃。
struct TabBarView: UIViewControllerRepresentable {
    let model: ConversionModel

    func makeUIViewController(context: Context) -> UITabBarController {
        let controller = UITabBarController()

        let home = makeTab(root: HomeView(model: model),
                           title: "首页",
                           symbol: "waveform")
        let profile = makeTab(root: ProfileView(model: model),
                              title: "我的",
                              symbol: "person.crop.circle")
        controller.viewControllers = [home, profile]

        controller.tabBar.tintColor = UIColor(named: "AccentColor")
        controller.tabBar.unselectedItemTintColor = .secondaryLabel

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .separator
        controller.tabBar.standardAppearance = appearance
        controller.tabBar.scrollEdgeAppearance = appearance
        controller.tabBar.isTranslucent = false

        return controller
    }

    func updateUIViewController(_ controller: UITabBarController, context: Context) {}

    private func makeTab<Content: View>(root: Content,
                                        title: String,
                                        symbol: String) -> UIViewController {
        let nav = UINavigationController(rootViewController: UIHostingController(rootView: root))
        // 页面内部有 SwiftUI NavigationStack，隐藏 UIKit 导航栏避免双层
        nav.setNavigationBarHidden(true, animated: false)
        nav.navigationBar.prefersLargeTitles = true
        nav.tabBarItem = UITabBarItem(title: title,
                                      image: UIImage(systemName: symbol),
                                      tag: 0)
        return nav
    }
}
