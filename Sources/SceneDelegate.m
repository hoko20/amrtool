//
//  SceneDelegate.m
//  AudioForge
//

#import "WQUI.h"

@implementation WQSceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.tintColor = WQAccentColor();

    WQConvertViewController *convert =
        [[WQConvertViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    WQFilesViewController *files =
        [[WQFilesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    WQToolsViewController *tools =
        [[WQToolsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    WQProfileViewController *profile =
        [[WQProfileViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    NSArray<UIViewController *> *roots = @[convert, files, tools, profile];
    NSArray<NSString *> *titles = @[@"转换", @"文件", @"工具", @"我的"];
    NSArray<NSString *> *symbols = @[@"waveform",
                                     @"doc.text",
                                     @"wrench.and.screwdriver",
                                     @"person.crop.circle"];

    NSMutableArray<UINavigationController *> *tabs = [NSMutableArray array];
    for (NSUInteger index = 0; index < roots.count; index++) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:roots[index]];
        nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[index]
                                                      image:[UIImage systemImageNamed:symbols[index]]
                                                        tag:(NSInteger)index];
        nav.navigationBar.prefersLargeTitles = YES;
        [tabs addObject:nav];
    }

    UITabBarController *tabBar = [UITabBarController new];
    tabBar.viewControllers = tabs.copy;
    tabBar.tabBar.tintColor = WQAccentColor();
    tabBar.tabBar.unselectedItemTintColor = UIColor.secondaryLabelColor;

    UITabBarAppearance *appearance = [UITabBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = UIColor.systemBackgroundColor;
    appearance.shadowColor = UIColor.separatorColor;
    tabBar.tabBar.standardAppearance = appearance;
    tabBar.tabBar.scrollEdgeAppearance = appearance;

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
}

@end
