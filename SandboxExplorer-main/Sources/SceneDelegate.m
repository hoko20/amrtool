//
//  SceneDelegate.m
//  SandboxExplorer
//

#import "WQUI.h"
#import "WQKit.h"

@implementation WQSceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions API_AVAILABLE(ios(13.0))
{
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

    WQHomeViewController *home = [[WQHomeViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    WQContainersViewController *containers = [[WQContainersViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    WQBrowserViewController *ownFiles = [[WQBrowserViewController alloc] initWithPath:WQDocumentsPath()
                                                                               title:@"我的文件"];
    WQToolsViewController *tools = [[WQToolsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];

    NSArray<UIViewController *> *roots = @[home, containers, ownFiles, tools];
    NSArray<NSString *> *titles = @[@"沙盒", @"容器", @"文件", @"工具"];
    NSArray<NSString *> *symbols = @[@"folder", @"square.grid.2x2", @"doc.text", @"wrench.and.screwdriver"];
    NSMutableArray<UINavigationController *> *tabs = [NSMutableArray array];
    for (NSUInteger i = 0; i < roots.count; i++) {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:roots[i]];
        nav.tabBarItem = [[UITabBarItem alloc] initWithTitle:titles[i]
                                                      image:[UIImage systemImageNamed:symbols[i]]
                                                        tag:(NSInteger)i];
        nav.navigationBar.prefersLargeTitles = YES;
        [tabs addObject:nav];
    }

    UITabBarController *tabBar = [UITabBarController new];
    tabBar.viewControllers = tabs.copy;
    self.window.rootViewController = tabBar;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidEnterBackground:(UIScene *)scene API_AVAILABLE(ios(13.0))
{
    WQLog(@"进入后台");
}

@end
