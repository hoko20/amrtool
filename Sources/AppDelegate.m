//
//  AppDelegate.m
//  AudioForge
//

#import "AFUI.h"

#pragma mark - 共用辅助

UIColor *AFAccentColor(void)
{
    UIColor *accent = [UIColor colorNamed:@"AccentColor"];
    return accent ?: [UIColor systemBlueColor];
}

NSString *AFDocumentsPath(void)
{
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
}

static NSString *const AFFormatDefaultsKey = @"AFOutputFormat";

AFOutputFormat AFCurrentFormat(void)
{
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:AFFormatDefaultsKey];
    if (value < AFOutputFormatSilk || value > AFOutputFormatM4A) {
        return AFOutputFormatSilk;
    }
    return (AFOutputFormat)value;
}

void AFSetCurrentFormat(AFOutputFormat format)
{
    [NSUserDefaults.standardUserDefaults setInteger:format forKey:AFFormatDefaultsKey];
}

NSString *AFFormatTitle(AFOutputFormat format)
{
    switch (format) {
        case AFOutputFormatSilk: return @"SILK · .aud";
        case AFOutputFormatNB:   return @"AMR-NB 12.2k";
        case AFOutputFormatWB:   return @"AMR-WB 23.85k";
        case AFOutputFormatM4A:  return @"M4A · AAC 96k";
    }
    return @"";
}

NSString *AFFormatSubtitle(AFOutputFormat format)
{
    switch (format) {
        case AFOutputFormatSilk: return @"微信 / QQ 语音条";
        case AFOutputFormatNB:   return @"兼容最好，电话音质";
        case AFOutputFormatWB:   return @"16kHz，明显更清晰";
        case AFOutputFormatM4A:  return @"接近原音，通用播放";
    }
    return @"";
}

NSString *AFFormatExtension(AFOutputFormat format)
{
    switch (format) {
        case AFOutputFormatSilk: return @"aud";
        case AFOutputFormatNB:
        case AFOutputFormatWB:   return @"amr";
        case AFOutputFormatM4A:  return @"m4a";
    }
    return @"amr";
}

NSString *AFFormatSummary(AFOutputFormat format)
{
    switch (format) {
        case AFOutputFormatSilk:
            return @"微信、QQ 语音条采用的格式，音质好、体积小；部分只认 AMR 的语音网关不支持。";
        case AFOutputFormatNB:
            return @"兼容性最好，几乎所有语音平台都能识别；8kHz 电话音质是 AMR-NB 的上限。";
        case AFOutputFormatWB:
            return @"AMR 家族最高档，16kHz 宽带语音，比 NB 明显清晰；个别老网关只接受 NB。";
        case AFOutputFormatM4A:
            return @"AAC 96kbps，接近原始音质，适合通用播放与存档；不是 AMR 格式。";
    }
    return @"";
}

NSArray<NSString *> *AFOutputFileNames(void)
{
    NSArray<NSString *> *contents = [[NSFileManager defaultManager]
                                     contentsOfDirectoryAtPath:AFDocumentsPath() error:nil];
    NSSet<NSString *> *suffixes = [NSSet setWithObjects:@"amr", @"aud", @"m4a", nil];
    NSMutableArray<NSString *> *matched = [NSMutableArray array];
    for (NSString *name in contents) {
        if ([suffixes containsObject:name.pathExtension.lowercaseString]) {
            [matched addObject:name];
        }
    }
    return [matched sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

NSString *AFSanitizedBaseName(NSString *name)
{
    NSString *base = name.stringByDeletingPathExtension;
    NSMutableCharacterSet *illegal = [NSMutableCharacterSet controlCharacterSet];
    [illegal addCharactersInString:@"/\\:*?\"<>|\n\r\t"];
    base = [[base componentsSeparatedByCharactersInSet:illegal] componentsJoinedByString:@"-"];
    base = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    while ([base containsString:@"--"]) {
        base = [base stringByReplacingOccurrencesOfString:@"--" withString:@"-"];
    }
    if (base.length > 80) {
        base = [base substringToIndex:80];
    }
    if (base.length == 0 || [base isEqualToString:@"."] || [base isEqualToString:@".."]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"yyyyMMdd-HHmmss";
        base = [NSString stringWithFormat:@"音频-%@", [formatter stringFromDate:[NSDate date]]];
    }
    return base;
}

NSURL *AFUniqueOutputURL(NSString *baseName, NSString *extension)
{
    NSString *directory = AFDocumentsPath();
    NSString *base = AFSanitizedBaseName(baseName);

    NSURL *url = [NSURL fileURLWithPath:[[directory stringByAppendingPathComponent:base]
                                         stringByAppendingPathExtension:extension]];
    NSInteger index = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        NSString *name = [NSString stringWithFormat:@"%@-%ld", base, (long)index];
        url = [NSURL fileURLWithPath:[[directory stringByAppendingPathComponent:name]
                                      stringByAppendingPathExtension:extension]];
        index++;
    }
    return url;
}

void AFCopyToPasteboard(NSString *text)
{
    [UIPasteboard generalPasteboard].string = text ?: @"";
}

void AFPresentAlert(UIViewController *from, NSString *title, NSString *message)
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ AFPresentAlert(from, title, message); });
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *host = from.navigationController ?: from;
    [host presentViewController:alert animated:YES completion:nil];
}

@implementation AFAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *configuration =
        [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                       sessionRole:connectingSceneSession.role];
    // 必须显式指定 SceneDelegate，否则窗口不会被创建
    configuration.delegateClass = AFSceneDelegate.class;
    return configuration;
}

@end
