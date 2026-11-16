//
//  AppDelegate.m
//  SandboxExplorer
//

#import "WQUI.h"
#import "WQKit.h"

@implementation WQAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    WQLog(@"SandboxExplorer 启动");
    WQLog(@"bundle id = %@", WQBundleIdentifier());
    WQLog(@"iOS = %@ (major %ld)", WQOSVersionString(), (long)WQOSMajorVersion());
    WQLog(@"home = %@", WQHomePath());
    if (!WQOS26OrLater()) {
        WQLog(@"警告：容器访问技术仅适用于 iOS 26.0 - 26.7.2 / 27.2；本设备主版本 %ld 不受支持",
              (long)WQOSMajorVersion());
    }
    if (!WQAppGroupReady()) {
        WQLog(@"警告：没有可用的 App Group，worse_query 无法签发 sandbox extension");
    }
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                               options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0))
{
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                         sessionRole:connectingSceneSession.role];
}

@end

#pragma mark - Shared UI helpers

void WQPresentAlert(UIViewController *from, NSString *title, NSString *message)
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ WQPresentAlert(from, title, message); });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *host = from.tabBarController ?: from.navigationController ?: from;
    [host presentViewController:alert animated:YES completion:nil];
}

void WQCopyToPasteboard(NSString *text)
{
    UIPasteboard.generalPasteboard.string = text ?: @"";
    WQLog(@"copied: %@", text);
}

UIAlertController *WQInputAlert(NSString *title, NSString *message, NSString *placeholder,
                                NSString *initial, void (^commit)(NSString *value))
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = placeholder;
        field.text = initial;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *value = weakAlert.textFields.firstObject.text ?: @"";
        if (commit) commit(value);
    }]];
    return alert;
}

UIColor *WQAccentColor(void)
{
    return UIColor.systemBlueColor;
}
