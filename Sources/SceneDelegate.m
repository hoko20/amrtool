//
//  SceneDelegate.m
//  AudioForge
//

#import "AFUI.h"

@implementation AFSceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions
{
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.tintColor = AFAccentColor();

    AFConvertViewController *convert =
        [[AFConvertViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    AFFilesViewController *files =
        [[AFFilesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    AFToolsViewController *tools =
        [[AFToolsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    AFProfileViewController *profile =
        [[AFProfileViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

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
    tabBar.tabBar.tintColor = AFAccentColor();

    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
}

@end
