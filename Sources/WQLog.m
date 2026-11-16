//
//  WQLog.m
//  SandboxExplorer
//

#import "WQKit.h"

static NSMutableString *gWQLogBuffer;
static NSLock *gWQLogLock;

static void WQLogEnsure(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gWQLogBuffer = [NSMutableString new];
        gWQLogLock = [NSLock new];
    });
}

void WQLog(NSString *format, ...)
{
    WQLogEnsure();
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"HH:mm:ss.SSS";
    NSString *stamp = [fmt stringFromDate:[NSDate date]];

    [gWQLogLock lock];
    [gWQLogBuffer appendFormat:@"[%@] %@\n", stamp, line];
    // Keep the in-memory log bounded; the UI shares the whole text on demand.
    if (gWQLogBuffer.length > 512 * 1024) {
        NSUInteger cut = gWQLogBuffer.length - 384 * 1024;
        NSRange newline = [gWQLogBuffer rangeOfString:@"\n"
                                              options:0
                                                range:NSMakeRange(cut, gWQLogBuffer.length - cut)];
        NSUInteger from = newline.location == NSNotFound ? cut : NSMaxRange(newline);
        [gWQLogBuffer deleteCharactersInRange:NSMakeRange(0, from)];
    }
    [gWQLogLock unlock];
}

NSString *WQLogText(void)
{
    WQLogEnsure();
    [gWQLogLock lock];
    NSString *text = [gWQLogBuffer copy] ?: @"";
    [gWQLogLock unlock];
    return text;
}

void WQLogClear(void)
{
    WQLogEnsure();
    [gWQLogLock lock];
    [gWQLogBuffer setString:@""];
    [gWQLogLock unlock];
}

#pragma mark - Environment

NSString *WQHomePath(void)
{
    return NSHomeDirectory();
}

NSString *WQDocumentsPath(void)
{
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
           ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
}

NSString *WQLibraryPath(void)
{
    return [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject]
           ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
}

NSString *WQCachesPath(void)
{
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]
           ?: [WQLibraryPath() stringByAppendingPathComponent:@"Caches"];
}

NSString *WQTmpPath(void)
{
    return NSTemporaryDirectory() ?: [NSHomeDirectory() stringByAppendingPathComponent:@"tmp"];
}

NSString *WQExportsPath(void)
{
    NSString *path = [WQDocumentsPath() stringByAppendingPathComponent:@"Exports"];
    [NSFileManager.defaultManager createDirectoryAtPath:path
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:nil];
    return path;
}

NSString *WQBundleIdentifier(void)
{
    return NSBundle.mainBundle.bundleIdentifier ?: @"(unknown)";
}

NSString *WQOSVersionString(void)
{
    return NSProcessInfo.processInfo.operatingSystemVersionString;
}

NSInteger WQOSMajorVersion(void)
{
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion;
}

BOOL WQOS26OrLater(void)
{
    return WQOSMajorVersion() >= 26;
}

BOOL WQOS27OrLater(void)
{
    return WQOSMajorVersion() >= 27;
}

NSString *WQNormalize(NSString *path)
{
    NSString *p = path.stringByStandardizingPath;
    if ([p hasPrefix:@"/var/"]) p = [@"/private" stringByAppendingString:p];
    return p;
}
