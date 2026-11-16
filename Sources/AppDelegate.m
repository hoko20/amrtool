//
//  AppDelegate.m
//  AudioForge
//

#import "WQUI.h"

#pragma mark - 共用辅助

UIColor *WQAccentColor(void)
{
    UIColor *accent = [UIColor colorNamed:@"AccentColor"];
    return accent ?: [UIColor systemBlueColor];
}

NSString *WQDocumentsPath(void)
{
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *const WQFormatDefaultsKey = @"WQOutputFormat";

WQOutputFormat WQCurrentFormat(void)
{
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:WQFormatDefaultsKey];
    if (value < WQOutputFormatSilk || value > WQOutputFormatM4A) {
        return WQOutputFormatSilk;
    }
    return (WQOutputFormat)value;
}

void WQSetCurrentFormat(WQOutputFormat format)
{
    [NSUserDefaults.standardUserDefaults setInteger:format forKey:WQFormatDefaultsKey];
}

NSString *WQFormatTitle(WQOutputFormat format)
{
    switch (format) {
        case WQOutputFormatSilk: return @"SILK · .aud";
        case WQOutputFormatNB:   return @"AMR-NB 12.2k";
        case WQOutputFormatWB:   return @"AMR-WB 23.85k";
        case WQOutputFormatM4A:  return @"M4A · AAC 96k";
    }
    return @"";
}

NSString *WQFormatSubtitle(WQOutputFormat format)
{
    switch (format) {
        case WQOutputFormatSilk: return @"微信 / QQ 语音条";
        case WQOutputFormatNB:   return @"兼容最好，电话音质";
        case WQOutputFormatWB:   return @"16kHz，明显更清晰";
        case WQOutputFormatM4A:  return @"接近原音，通用播放";
    }
    return @"";
}

NSString *WQFormatExtension(WQOutputFormat format)
{
    switch (format) {
        case WQOutputFormatSilk: return @"aud";
        case WQOutputFormatNB:
        case WQOutputFormatWB:   return @"amr";
        case WQOutputFormatM4A:  return @"m4a";
    }
    return @"amr";
}

NSString *WQFormatSummary(WQOutputFormat format)
{
    switch (format) {
        case WQOutputFormatSilk:
            return @"微信、QQ 语音条采用的格式，音质好、体积小；部分只认 AMR 的语音网关不支持。";
        case WQOutputFormatNB:
            return @"兼容性最好，几乎所有语音平台都能识别；8kHz 电话音质是 AMR-NB 的上限。";
        case WQOutputFormatWB:
            return @"AMR 家族最高档，16kHz 宽带语音，比 NB 明显清晰；个别老网关只接受 NB。";
        case WQOutputFormatM4A:
            return @"AAC 96kbps，接近原始音质，适合通用播放与存档；不是 AMR 格式。";
    }
    return @"";
}

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
    UIViewController *host = from.navigationController ?: from;
    [host presentViewController:alert animated:YES completion:nil];
}

@implementation WQAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options
{
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                         sessionRole:connectingSceneSession.role];
}

@end
