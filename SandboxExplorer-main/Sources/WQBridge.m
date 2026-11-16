//
//  WQBridge.m
//  SandboxExplorer
//
//  Sandbox-extension acquisition, reimplemented from worse_query by Taj C
//  (forcequitOS), https://github.com/forcequitOS/worse_query, GPL-3.0-or-later.
//
//  Principle: containermanagerd issues a sandbox extension for the App Group
//  container. If the group's Library/Caches is a symlink pointing at an
//  arbitrary existing path at the moment of the query, the issued token covers
//  that target instead. Consuming the token grants this process normal POSIX
//  access to the target subtree.
//
//  Improvements over the upstream PoC in this file:
//   - the original Caches directory is preserved by rename()/rename() instead
//     of being deleted, with crash recovery on the next acquisition;
//   - an flock serialises queries (the swap is process-global state);
//   - handles are cached in a bounded LRU so long browsing sessions stay under
//     the kernel's per-process extension limit;
//   - both query flag sets are attempted and the working one is remembered;
//   - a consumed token is verified to actually open the target.
//

#import "WQKit.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <xpc/xpc.h>

#pragma mark - libsystem_containermanager

typedef void *(*WQCQCreateFn)(void);
typedef void (*WQCQSetU64Fn)(void *, uint64_t);
typedef void (*WQCQSetIDsFn)(void *, xpc_object_t);
typedef void *(*WQCQResultFn)(void *);
typedef void (*WQCQFreeFn)(void *);
typedef char *(*WQCQTokenFn)(void *);
typedef int64_t (*WQExtConsumeFn)(const char *);
typedef int (*WQExtReleaseFn)(int64_t);

static void *gMgr;
static WQCQCreateFn gCreate;
static WQCQSetU64Fn gSetClass, gSetFlags, gSetPart;
static WQCQSetIDsFn gSetGroups;
static WQCQResultFn gSingleResult;
static WQCQFreeFn gFreeQuery;
static WQCQTokenFn gCopyToken;
static WQExtConsumeFn gConsume;
static WQExtReleaseFn gRelease;
static int gResolveFailed = 0;

static void WQResolveSymbols(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gMgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        if (!gMgr) { gResolveFailed = 1; return; }
        gCreate       = (WQCQCreateFn)dlsym(gMgr, "container_query_create");
        gSetClass     = (WQCQSetU64Fn)dlsym(gMgr, "container_query_set_class");
        gSetGroups    = (WQCQSetIDsFn)dlsym(gMgr, "container_query_set_group_identifiers");
        gSetFlags     = (WQCQSetU64Fn)dlsym(gMgr, "container_query_operation_set_flags");
        gSetPart      = (WQCQSetU64Fn)dlsym(gMgr, "container_query_operation_set_part");
        gSingleResult = (WQCQResultFn)dlsym(gMgr, "container_query_get_single_result");
        gFreeQuery    = (WQCQFreeFn)dlsym(gMgr, "container_query_free");
        gCopyToken    = (WQCQTokenFn)dlsym(gMgr, "container_copy_sandbox_token");
        gConsume      = (WQExtConsumeFn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
        gRelease      = (WQExtReleaseFn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
        if (!gCreate || !gSetClass || !gSetGroups || !gSetFlags || !gSetPart ||
            !gSingleResult || !gFreeQuery || !gCopyToken || !gConsume) {
            gResolveFailed = 1;
        }
    });
}

void WQReleaseHandle(int64_t handle)
{
    if (handle < 0) return;
    WQResolveSymbols();
    if (gRelease) gRelease(handle);
}

#pragma mark - App group discovery

typedef void *(*WQSecTaskCreateFn)(CFAllocatorRef);
typedef CFTypeRef (*WQSecTaskCopyValueFn)(void *, CFStringRef, CFErrorRef *);

NSArray<NSString *> *WQEntitledGroups(void)
{
    static NSArray<NSString *> *groups;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray<NSString *> *out = [NSMutableArray array];
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
        WQSecTaskCreateFn create = (WQSecTaskCreateFn)dlsym(RTLD_DEFAULT, "SecTaskCreateFromSelf");
        WQSecTaskCopyValueFn copy = (WQSecTaskCopyValueFn)dlsym(RTLD_DEFAULT, "SecTaskCopyValueForEntitlement");
        if (security) {
            if (!create) create = (WQSecTaskCreateFn)dlsym(security, "SecTaskCreateFromSelf");
            if (!copy) copy = (WQSecTaskCopyValueFn)dlsym(security, "SecTaskCopyValueForEntitlement");
        }
        if (create && copy) {
            void *task = create(kCFAllocatorDefault);
            if (task) {
                CFTypeRef value = copy(task, CFSTR("com.apple.security.application-groups"), NULL);
                if (value) {
                    NSArray *raw = (__bridge_transfer NSArray *)value;
                    for (id item in raw) {
                        if ([item isKindOfClass:NSString.class]) [out addObject:item];
                    }
                }
                CFRelease((CFTypeRef)task);
            }
        }
        groups = out.copy;
    });
    return groups ?: @[];
}

NSString *WQAppGroup(void)
{
    static NSString *group;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray<NSString *> *candidates = [WQEntitledGroups() mutableCopy];
        // configure.sh also writes the group into Info.plist, so a re-signed
        // build still works even when SecTask is unavailable.
        NSString *configured = [NSBundle.mainBundle objectForInfoDictionaryKey:@"WQAppGroupIdentifier"];
        if ([configured isKindOfClass:NSString.class] && configured.length) [candidates addObject:configured];
        for (NSString *candidate in candidates) {
            if ([fm containerURLForSecurityApplicationGroupIdentifier:candidate]) {
                group = candidate;
                break;
            }
        }
        WQLog(@"App Group: %@ (entitled: %@)", group ?: @"NONE",
              candidates.count ? [candidates componentsJoinedByString:@", "] : @"none");
        if (!group) {
            WQLog(@"No usable App Group. Sign the app with a profile that contains "
                   "com.apple.security.application-groups, then reinstall.");
        }
    });
    return group;
}

BOOL WQAppGroupReady(void)
{
    return WQAppGroup() != nil;
}

#pragma mark - Caches symlink swap

static NSString *WQSwapBackupPath(NSString *libraryPath)
{
    return [libraryPath stringByAppendingPathComponent:@".sandboxexplorer-caches-original"];
}

static BOOL WQIsSymlink(const char *path)
{
    struct stat st;
    if (lstat(path, &st) != 0) return NO;
    return S_ISLNK(st.st_mode);
}

/// Restore an interrupted swap: the backup directory must win over the link.
static void WQRecoverSwap(NSString *libraryPath)
{
    NSString *caches = [libraryPath stringByAppendingPathComponent:@"Caches"];
    NSString *backup = WQSwapBackupPath(libraryPath);
    struct stat st;
    if (lstat(backup.fileSystemRepresentation, &st) != 0) return;

    if (WQIsSymlink(caches.fileSystemRepresentation)) {
        if (unlink(caches.fileSystemRepresentation) != 0) {
            WQLog(@"swap recovery: cannot unlink Caches link (%s)", strerror(errno));
            return;
        }
        if (rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
            WQLog(@"swap recovery: cannot restore Caches (%s)", strerror(errno));
        } else {
            WQLog(@"swap recovery: restored the original Library/Caches");
        }
    } else {
        // A real directory is already in place; keep the backup untouched rather
        // than recursively deleting anything the app does not own.
        WQLog(@"swap recovery: Caches is a real directory; preserved backup at %@", backup);
    }
}

static BOOL WQSwapBegin(NSString *libraryPath, NSString *target)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:libraryPath
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
    WQRecoverSwap(libraryPath);

    NSString *caches = [libraryPath stringByAppendingPathComponent:@"Caches"];
    NSString *backup = WQSwapBackupPath(libraryPath);
    struct stat st;
    BOOL hadCaches = (lstat(caches.fileSystemRepresentation, &st) == 0);
    if (hadCaches) {
        // If an unrecoverable backup is still lying around, do not overwrite it.
        if (lstat(backup.fileSystemRepresentation, &st) == 0) return NO;
        if (rename(caches.fileSystemRepresentation, backup.fileSystemRepresentation) != 0) {
            WQLog(@"swap begin: rename Caches -> backup failed (%s)", strerror(errno));
            return NO;
        }
    }
    if (symlink(target.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
        WQLog(@"swap begin: symlink failed (%s)", strerror(errno));
        if (hadCaches) rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation);
        return NO;
    }
    return YES;
}

static void WQSwapEnd(NSString *libraryPath)
{
    NSString *caches = [libraryPath stringByAppendingPathComponent:@"Caches"];
    NSString *backup = WQSwapBackupPath(libraryPath);
    struct stat st;

    if (WQIsSymlink(caches.fileSystemRepresentation)) {
        if (unlink(caches.fileSystemRepresentation) != 0) {
            WQLog(@"swap end: cannot remove Caches link (%s)", strerror(errno));
        }
    }
    if (lstat(backup.fileSystemRepresentation, &st) == 0) {
        if (rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
            WQLog(@"swap end: cannot restore Caches (%s)", strerror(errno));
        }
    } else if (lstat(caches.fileSystemRepresentation, &st) != 0) {
        [NSFileManager.defaultManager createDirectoryAtPath:caches
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
    }
}

#pragma mark - One query

static int64_t WQRunQuery(NSString *target, NSString *group, BOOL altFlags)
{
    WQResolveSymbols();
    if (gResolveFailed) return -2;

    void *query = gCreate();
    if (!query) return -3;

    char *token = NULL;
    int64_t handle = -5;
    @try {
        gSetClass(query, 7);   // appGroup containers
        xpc_object_t identifier = xpc_string_create(group.UTF8String);
        gSetGroups(query, identifier);
        gSetPart(query, 3);    // Library/Caches is the swapped path
        gSetFlags(query, altFlags ? 0x0000000800000000ULL : 0x0000008000000000ULL);

        void *result = gSingleResult(query);
        if (result) {
            token = gCopyToken(result);
            handle = token ? gConsume(token) : -6;
            if (token && handle < 0) handle = -7;
        } else {
            handle = -5;
        }
    } @catch (NSException *exception) {
        WQLog(@"query exception: %@", exception.reason);
        handle = -9;
    } @finally {
        if (token) free(token);
        gFreeQuery(query);
    }
    return handle;
}

int64_t WQQueryRaw(NSString *path, BOOL altFlags, BOOL createDir)
{
    NSString *group = WQAppGroup();
    if (!group) return -1;
    NSString *target = WQNormalize(path);

    if (!createDir) {
        struct stat st;
        if (lstat(target.fileSystemRepresentation, &st) != 0) return -255;
    }

    NSURL *root = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
    if (!root) return -1;
    NSString *libraryPath = [root.path stringByAppendingPathComponent:@"Library"];
    [NSFileManager.defaultManager createDirectoryAtPath:libraryPath
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

    NSString *lockPath = [libraryPath stringByAppendingPathComponent:@".sandboxexplorer-query.lock"];
    int lock = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (lock < 0) return -4;
    if (flock(lock, LOCK_EX) != 0) { close(lock); return -4; }

    int64_t handle = -4;
    if (WQSwapBegin(libraryPath, target)) {
        handle = WQRunQuery(target, group, altFlags);
        WQSwapEnd(libraryPath);
    }
    flock(lock, LOCK_UN);
    close(lock);
    WQLog(@"query(%@, flags=%@): handle=%lld", target, altFlags ? @"alt" : @"std", (long long)handle);
    return handle;
}

#pragma mark - Bounded grant cache

static NSMutableDictionary<NSString *, NSNumber *> *gGrants;
static NSMutableArray<NSString *> *gGrantOrder;
static NSRecursiveLock *gGrantLock;
static const NSUInteger kWQMaxGrants = 192;
static int gPreferAlt = -1;

static void WQGrantEnsure(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gGrants = [NSMutableDictionary new];
        gGrantOrder = [NSMutableArray new];
        gGrantLock = [NSRecursiveLock new];
    });
}

/// A consumed token is only useful if the target became openable. EACCES is
/// an ordinary Unix permission issue and a token will never fix that; EPERM is
/// the sandbox denial that matters.
static BOOL WQTokenOpens(NSString *path)
{
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd >= 0) { close(fd); return YES; }
    return errno != EPERM;
}

int64_t WQGrant(NSString *path)
{
    WQGrantEnsure();
    NSString *key = WQNormalize(path);

    [gGrantLock lock];
    NSNumber *cached = gGrants[key];
    if (cached) {
        [gGrantOrder removeObject:key];
        [gGrantOrder addObject:key];
        [gGrantLock unlock];
        return cached.longLongValue;
    }
    while (gGrantOrder.count >= kWQMaxGrants) {
        NSString *oldest = gGrantOrder.firstObject;
        WQReleaseHandle(gGrants[oldest].longLongValue);
        [gGrants removeObjectForKey:oldest];
        [gGrantOrder removeObjectAtIndex:0];
    }

    struct stat st;
    if (lstat(key.fileSystemRepresentation, &st) != 0) {
        [gGrantLock unlock];
        return -255;   // worse_query needs an existing target
    }

    BOOL altFirst = gPreferAlt >= 0 ? (BOOL)gPreferAlt : (!WQOS27OrLater());
    int64_t handle = WQQueryRaw(key, altFirst, NO);
    BOOL usedAlt = altFirst;

    if (handle >= 0 && !WQTokenOpens(key)) {
        WQLog(@"grant: token for %@ did not open it (%@ flags)", key, altFirst ? @"alt" : @"std");
        WQReleaseHandle(handle);
        handle = -8;
    }
    if (handle < 0 && handle != -1 && handle != -2) {
        int64_t other = WQQueryRaw(key, !altFirst, NO);
        if (other >= 0 && !WQTokenOpens(key)) {
            WQReleaseHandle(other);
            other = -8;
        }
        if (other >= 0) { handle = other; usedAlt = !altFirst; }
    }
    if (handle >= 0 && gPreferAlt < 0) {
        gPreferAlt = usedAlt;
        WQLog(@"grant: %@ query flags work on this device", usedAlt ? @"alternative" : @"standard");
    }
    if (handle >= 0) {
        gGrants[key] = @(handle);
        [gGrantOrder addObject:key];
    } else {
        WQLog(@"grant FAILED %@: %@", key, WQGrantErrorText(handle));
    }
    [gGrantLock unlock];
    return handle;
}

BOOL WQEnsure(NSString *path, NSString **error)
{
    int64_t handle = WQGrant(path);
    if (handle >= 0) return YES;
    if (error) *error = [NSString stringWithFormat:@"无法获取沙盒扩展：%@", WQGrantErrorText(handle)];
    return NO;
}

void WQReleaseAllGrants(void)
{
    WQGrantEnsure();
    [gGrantLock lock];
    for (NSString *key in gGrantOrder) WQReleaseHandle(gGrants[key].longLongValue);
    [gGrants removeAllObjects];
    [gGrantOrder removeAllObjects];
    [gGrantLock unlock];
    WQLog(@"released every sandbox extension");
}

NSUInteger WQGrantCount(void)
{
    WQGrantEnsure();
    [gGrantLock lock];
    NSUInteger count = gGrantOrder.count;
    [gGrantLock unlock];
    return count;
}

NSArray<NSString *> *WQGrantPaths(void)
{
    WQGrantEnsure();
    [gGrantLock lock];
    NSArray *paths = gGrantOrder.copy;
    [gGrantLock unlock];
    return paths;
}

NSString *WQGrantErrorText(int64_t code)
{
    switch (code) {
        case -1:   return @"App Group 不可用（entitlement 或描述文件不含该 group）";
        case -2:   return @"系统不支持（无法解析 libsystem_containermanager 符号）";
        case -3:   return @"container_query_create 失败";
        case -4:   return @"无法建立/锁定 Library/Caches 交换点";
        case -5:   return @"containermanagerd 拒绝了查询";
        case -6:   return @"内核拒绝签发 sandbox extension";
        case -7:   return @"token 已签发但 consume 失败";
        case -8:   return @"token 未能打开目标路径";
        case -9:   return @"查询过程抛出异常";
        case -255: return @"目标路径不存在";
        default:   return [NSString stringWithFormat:@"未知错误 %lld", (long long)code];
    }
}
