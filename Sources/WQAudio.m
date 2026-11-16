//
//  WQAudio.m
//  SandboxExplorer
//

#import "WQAudio.h"
#import "WQKit.h"
#import <math.h>

static NSString *const WQAudioFormatKey = @"WQAudioFormat";

NSString *WQAudioFormatTitle(WQAudioFormat format)
{
    switch (format) {
        case WQAudioFormatSilk:  return @"SILK 语音条";
        case WQAudioFormatAMRNB: return @"AMR-NB";
        case WQAudioFormatAMRWB: return @"AMR-WB";
        case WQAudioFormatM4A:   return @"M4A 音频";
    }
    return @"SILK 语音条";
}

NSString *WQAudioFormatDetail(WQAudioFormat format)
{
    switch (format) {
        case WQAudioFormatSilk:  return @"24 kHz · 25 kbps · 微信 / QQ .aud";
        case WQAudioFormatAMRNB: return @"8 kHz · 12.2 kbps · 兼容性最好";
        case WQAudioFormatAMRWB: return @"16 kHz · 23.85 kbps · 更清晰";
        case WQAudioFormatM4A:   return @"AAC 96 kbps · 通用播放器";
    }
    return @"";
}

NSString *WQAudioFormatExtension(WQAudioFormat format)
{
    switch (format) {
        case WQAudioFormatSilk:  return @"aud";
        case WQAudioFormatAMRNB: return @"amr";
        case WQAudioFormatAMRWB: return @"amr";
        case WQAudioFormatM4A:   return @"m4a";
    }
    return @"aud";
}

WQAudioFormat WQAudioCurrentFormat(void)
{
    NSInteger value = [NSUserDefaults.standardUserDefaults integerForKey:WQAudioFormatKey];
    if (value < WQAudioFormatSilk || value > WQAudioFormatM4A) return WQAudioFormatSilk;
    return (WQAudioFormat)value;
}

void WQAudioSetCurrentFormat(WQAudioFormat format)
{
    [NSUserDefaults.standardUserDefaults setInteger:format forKey:WQAudioFormatKey];
}

NSString *WQAudioOutputDirectory(void)
{
    NSString *dir = [WQDocumentsPath() stringByAppendingPathComponent:@"AudioForge"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    return dir;
}

NSArray<NSString *> *WQAudioOutputFiles(void)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *dir = WQAudioOutputDirectory();
    NSArray<NSString *> *names = [manager contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    for (NSString *name in names) {
        if ([@[@"aud", @"amr", @"m4a"] containsObject:name.pathExtension.lowercaseString]) {
            [files addObject:name];
        }
    }
    [files sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSDate *da = [manager attributesOfItemAtPath:[dir stringByAppendingPathComponent:a]
                                               error:nil][NSFileModificationDate];
        NSDate *db = [manager attributesOfItemAtPath:[dir stringByAppendingPathComponent:b]
                                               error:nil][NSFileModificationDate];
        return [(db ?: NSDate.distantPast) compare:(da ?: NSDate.distantPast)];
    }];
    return files;
}

NSString *WQAudioBaseName(NSString *name)
{
    NSString *base = name.stringByDeletingPathExtension;
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    base = [[base componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"-"];
    base = [base stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return base.length ? base : @"音频";
}

NSURL *WQAudioUniqueOutputURL(NSString *baseName, NSString *extension)
{
    NSString *dir = WQAudioOutputDirectory();
    NSString *base = WQAudioBaseName(baseName);
    NSURL *url = [NSURL fileURLWithPath:
                  [dir stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"%@.%@", base, extension]]];
    NSInteger index = 1;
    while ([NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        url = [NSURL fileURLWithPath:
               [dir stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@-%ld.%@", base, (long)index++, extension]]];
    }
    return url;
}

void WQAudioSetTableHeader(UITableView *tableView, NSString *text)
{
    CGFloat width = tableView.bounds.size.width;
    if (width <= 0) width = UIScreen.mainScreen.bounds.size.width;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = text;
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];

    CGSize fitted = [container systemLayoutSizeFittingSize:CGSizeMake(width, UILayoutFittingCompressedSize.height)
                          withHorizontalFittingPriority:UILayoutPriorityRequired
                                verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    container.frame = CGRectMake(0, 0, width, ceil(fitted.height));
    tableView.tableHeaderView = container;
}
