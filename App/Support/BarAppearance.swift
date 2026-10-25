import UIKit

/// Colors the navigation bars and tab bars for the Night theme. SwiftUI can tint them, but can't color a large
/// navigation title, so this goes through UIKit's appearance API.
///
/// Nothing here runs until Night has been shown once in this launch, so Light, Dark and System keep the stock bars.
@MainActor
enum BarAppearance {
    private static var hasStyledNight = false

    static func apply(night: Bool) {
        guard night || hasStyledNight else { return }
        hasStyledNight = true
        configureProxies(night: night)
        restyleExistingBars(night: night)
        // At launch the first call can run before SwiftUI has built its controllers; look again next turn.
        DispatchQueue.main.async { restyleExistingBars(night: night) }
    }

    private static func restyleExistingBars(night: Bool) {
        for window in windows() {
            restyle(window, night: night)
            if let root = window.rootViewController {
                restyle(root, night: night)
            }
        }
    }

    // MARK: Appearances

    private static func navigationAppearance(scrolledUnder: Bool) -> UINavigationBarAppearance {
        let appearance = UINavigationBarAppearance()
        if scrolledUnder {
            appearance.configureWithDefaultBackground()
        } else {
            appearance.configureWithTransparentBackground()
        }
        appearance.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.nightPrimaryText)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(AppTheme.nightPrimaryText)]
        return appearance
    }

    private static func tabAppearance() -> UITabBarAppearance {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        let normal = UIColor(AppTheme.nightSecondaryText)
        let selected = UIColor(AppTheme.nightAccent)
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = normal
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        return appearance
    }

    /// For bars created later (sheets, pushed screens).
    private static func configureProxies(night: Bool) {
        let navigation = UINavigationBar.appearance()
        let tab = UITabBar.appearance()
        if night {
            navigation.standardAppearance = navigationAppearance(scrolledUnder: true)
            navigation.scrollEdgeAppearance = navigationAppearance(scrolledUnder: false)
            navigation.compactAppearance = navigationAppearance(scrolledUnder: true)
            let tabs = tabAppearance()
            tab.standardAppearance = tabs
            tab.scrollEdgeAppearance = tabs
            tab.unselectedItemTintColor = UIColor(AppTheme.nightSecondaryText)
            style(UISegmentedControl.appearance(), night: true)
        } else {
            navigation.standardAppearance = UINavigationBarAppearance()
            navigation.scrollEdgeAppearance = nil
            navigation.compactAppearance = nil
            tab.standardAppearance = UITabBarAppearance()
            tab.scrollEdgeAppearance = nil
            tab.unselectedItemTintColor = nil
            style(UISegmentedControl.appearance(), night: false)
        }
    }

    // MARK: Existing bars

    private static func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }

    /// On recent iOS the floating tab bar isn't a `UITabBar` in the view tree; style the controller's own bar too.
    private static func restyle(_ controller: UIViewController, night: Bool) {
        if let tabs = controller as? UITabBarController {
            style(tabs.tabBar, night: night)
        }
        for child in controller.children {
            restyle(child, night: night)
        }
        if let presented = controller.presentedViewController {
            restyle(presented, night: night)
        }
    }

    private static func restyle(_ view: UIView, night: Bool) {
        if let bar = view as? UINavigationBar {
            if night {
                bar.standardAppearance = navigationAppearance(scrolledUnder: true)
                bar.scrollEdgeAppearance = navigationAppearance(scrolledUnder: false)
                bar.compactAppearance = navigationAppearance(scrolledUnder: true)
            } else {
                bar.standardAppearance = UINavigationBarAppearance()
                bar.scrollEdgeAppearance = nil
                bar.compactAppearance = nil
            }
        } else if let bar = view as? UITabBar {
            style(bar, night: night)
        } else if let control = view as? UISegmentedControl {
            style(control, night: night)
        }
        for subview in view.subviews {
            restyle(subview, night: night)
        }
    }

    private static func style(_ bar: UITabBar, night: Bool) {
        if night {
            let appearance = tabAppearance()
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.unselectedItemTintColor = UIColor(AppTheme.nightSecondaryText)
        } else {
            bar.standardAppearance = UITabBarAppearance()
            bar.scrollEdgeAppearance = nil
            bar.unselectedItemTintColor = nil
        }
    }

    /// Segmented pickers (Trends range) would otherwise be a bright gray pill with white labels.
    private static func style(_ control: UISegmentedControl, night: Bool) {
        if night {
            control.selectedSegmentTintColor = UIColor(AppTheme.nightSeparator)
            control.setTitleTextAttributes([.foregroundColor: UIColor(AppTheme.nightSecondaryText)], for: .normal)
            control.setTitleTextAttributes([.foregroundColor: UIColor(AppTheme.nightPrimaryText)], for: .selected)
        } else {
            control.selectedSegmentTintColor = nil
            control.setTitleTextAttributes(nil, for: .normal)
            control.setTitleTextAttributes(nil, for: .selected)
        }
    }
}
