//
//  WQFileOps.m
//  SandboxExplorer
//
//  POSIX file operations with transparent sandbox-extension retry. Every
//  operation first tries the ordinary syscall; on EPERM/EACCES it asks
//  WQBridge for a token covering the relevant directory (writes need the
//  parent directory covered, not just the file) and retries once.
//

#import "WQKit.h"

#import <dirent.h>
#import <errno.h>
#import <fcntl.h>
#import <string.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/xattr.h>

@implementation WQItem
@end

static BOOL WQDenied(void)
{
    return errno == EPERM || errno == EACCES;
}

static NSString *WQErr(void)
{
    return [NSString stringWithFormat:@"%s (errno %d)", strerror(errno), errno];
}

static void WQSetError(NSString **error, NSString *text)
{
    if (error) *error = text;
}

static NSString *WQParent(NSString *path)
{
    NSString *parent = path.stringByDeletingLastPathComponent;
    return parent.length ? parent : @"/";
}

#pragma mark - Open helpers

static int WQOpenRead(NSString *path, NSString **error)
{
    NSString *p = WQNormalize(path);
    const char *c = p.fileSystemRepresentation;
    int fd = open(c, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd >= 0) return fd;
    if (!WQDenied()) { WQSetError(error, WQErr()); return -1; }

    WQEnsure(WQParent(p), nil);
    fd = open(c, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd >= 0) return fd;
    if (!WQDenied()) { WQSetError(error, WQErr()); return -1; }

    WQEnsure(p, nil);
    fd = open(c, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) WQSetError(error, WQErr());
    return fd;
}

static int WQOpenWrite(NSString *path, int flags, mode_t mode, NSString **error)
{
    NSString *p = WQNormalize(path);
    const char *c = p.fileSystemRepresentation;
    int fd = open(c, flags | O_NOFOLLOW | O_CLOEXEC, mode);
    if (fd >= 0) return fd;
    if (!WQDenied()) { WQSetError(error, WQErr()); return -1; }

    WQEnsure(WQParent(p), nil);
    fd = open(c, flags | O_NOFOLLOW | O_CLOEXEC, mode);
    if (fd < 0) WQSetError(error, WQErr());
    return fd;
}

static BOOL WQWriteAll(int fd, const void *bytes, size_t length, NSString **error)
{
    const uint8_t *cursor = bytes;
    size_t left = length;
    while (left > 0) {
        ssize_t n = write(fd, cursor, left);
        if (n < 0) {
            if (errno == EINTR) continue;
            WQSetError(error, WQErr());
            return NO;
        }
        if (n == 0) { WQSetError(error, @"write returned 0 bytes"); return NO; }
        cursor += n;
        left -= (size_t)n;
    }
    return YES;
}

static BOOL WQCloseChecked(int fd, NSString **error)
{
    if (close(fd) != 0) {
        WQSetError(error, WQErr());
        return NO;
    }
    return YES;
}

static BOOL WQStreamToLocal(int srcFd, NSString *dst, NSString **error)
{
    NSString *d = WQNormalize(dst);
    [[NSFileManager defaultManager] createDirectoryAtPath:d.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    int out = open(d.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (out < 0) { WQSetError(error, WQErr()); return NO; }

    uint8_t buffer[64 * 1024];
    BOOL ok = YES;
    for (;;) {
        ssize_t n = read(srcFd, buffer, sizeof(buffer));
        if (n < 0) {
            if (errno == EINTR) continue;
            WQSetError(error, WQErr());
            ok = NO;
            break;
        }
        if (n == 0) break;
        if (!WQWriteAll(out, buffer, (size_t)n, error)) { ok = NO; break; }
    }
    if (close(out) != 0 && ok) { WQSetError(error, WQErr()); ok = NO; }
    return ok;
}

#pragma mark - Listing

NSArray<WQItem *> *WQList(NSString *dir, NSString **error)
{
    NSString *d = WQNormalize(dir);
    DIR *handle = opendir(d.fileSystemRepresentation);
    if (!handle) {
        if (WQDenied()) {
            WQEnsure(d, nil);
            handle = opendir(d.fileSystemRepresentation);
        }
        if (!handle) { WQSetError(error, WQErr()); return nil; }
    }

    NSMutableArray<WQItem *> *items = [NSMutableArray array];
    struct dirent *entry;
    while ((entry = readdir(handle)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if (!name) {
            name = [[NSFileManager defaultManager]
                    stringWithFileSystemRepresentation:entry->d_name
                    length:strlen(entry->d_name)] ?: @"(unnamed)";
        }
        NSString *path = [d stringByAppendingPathComponent:name];
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0) {
            // A child that cannot be stat'ed may still need its own token.
            WQGrant(path);
            if (lstat(path.fileSystemRepresentation, &st) != 0) memset(&st, 0, sizeof(st));
        }
        WQItem *item = [WQItem new];
        item.name = name;
        item.path = path;
        item.directory = S_ISDIR(st.st_mode);
        item.symbolicLink = S_ISLNK(st.st_mode);
        item.size = (uint64_t)MAX(0, (int64_t)st.st_size);
        item.inode = (uint64_t)st.st_ino;
        item.mode = st.st_mode;
        item.mtime = st.st_mtime;
        [items addObject:item];
    }
    closedir(handle);

    [items sortUsingComparator:^NSComparisonResult(WQItem *a, WQItem *b) {
        if (a.directory != b.directory) return a.directory ? NSOrderedAscending : NSOrderedDescending;
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    return items.copy;
}

#pragma mark - Read / write

NSData *WQRead(NSString *path, NSUInteger maxBytes, NSString **error)
{
    int fd = WQOpenRead(path, error);
    if (fd < 0) return nil;

    struct stat st = {0};
    uint64_t limit = maxBytes ?: UINT64_MAX;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && maxBytes == 0) {
        limit = (uint64_t)st.st_size;
    }
    NSMutableData *data = [NSMutableData data];
    uint8_t buffer[64 * 1024];
    BOOL ok = YES;
    while (data.length < limit) {
        size_t want = (size_t)MIN((uint64_t)sizeof(buffer), limit - data.length);
        ssize_t n = read(fd, buffer, want);
        if (n < 0) {
            if (errno == EINTR) continue;
            WQSetError(error, WQErr());
            ok = NO;
            break;
        }
        if (n == 0) break;
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    if (!WQCloseChecked(fd, error) && ok) ok = NO;
    return ok ? data.copy : nil;
}

BOOL WQWrite(NSString *path, NSData *data, NSString **error)
{
    int fd = WQOpenWrite(path, O_WRONLY | O_TRUNC, 0644, error);
    if (fd < 0) return NO;
    BOOL ok = WQWriteAll(fd, data.bytes, data.length, error);
    if (!WQCloseChecked(fd, error) && ok) ok = NO;
    if (ok) WQLog(@"write %@ (%lu bytes)", path, (unsigned long)data.length);
    return ok;
}

BOOL WQCreateFile(NSString *path, NSData *data, NSString **error)
{
    int fd = WQOpenWrite(path, O_WRONLY | O_CREAT | O_EXCL, 0644, error);
    if (fd < 0) return NO;
    BOOL ok = WQWriteAll(fd, data.bytes, data.length, error);
    if (!WQCloseChecked(fd, error) && ok) ok = NO;
    if (!ok) unlink(WQNormalize(path).fileSystemRepresentation);
    else WQLog(@"create file %@ (%lu bytes)", path, (unsigned long)data.length);
    return ok;
}

BOOL WQCreateDir(NSString *path, NSString **error)
{
    NSString *p = WQNormalize(path);
    if (mkdir(p.fileSystemRepresentation, 0755) == 0) { WQLog(@"create dir %@", p); return YES; }
    if (!WQDenied()) { WQSetError(error, WQErr()); return NO; }
    WQEnsure(WQParent(p), nil);
    if (mkdir(p.fileSystemRepresentation, 0755) != 0) { WQSetError(error, WQErr()); return NO; }
    WQLog(@"create dir %@", p);
    return YES;
}

BOOL WQDelete(NSString *path, NSString **error)
{
    NSString *p = WQNormalize(path);
    struct stat st;
    if (lstat(p.fileSystemRepresentation, &st) != 0) { WQSetError(error, WQErr()); return NO; }
    // Deliberately non-recursive: rmdir only succeeds on an empty directory.
    int rc = S_ISDIR(st.st_mode) ? rmdir(p.fileSystemRepresentation)
                                 : unlink(p.fileSystemRepresentation);
    if (rc != 0 && WQDenied()) {
        WQEnsure(WQParent(p), nil);
        rc = S_ISDIR(st.st_mode) ? rmdir(p.fileSystemRepresentation)
                                 : unlink(p.fileSystemRepresentation);
    }
    if (rc != 0) { WQSetError(error, WQErr()); return NO; }
    WQLog(@"delete %@", p);
    return YES;
}

BOOL WQRename(NSString *path, NSString *newName, NSString **error)
{
    if (newName.length == 0 || [newName containsString:@"/"]) {
        WQSetError(error, @"名称不能为空且不能包含 /");
        return NO;
    }
    NSString *p = WQNormalize(path);
    NSString *dest = [WQParent(p) stringByAppendingPathComponent:newName];
    if (rename(p.fileSystemRepresentation, dest.fileSystemRepresentation) == 0) {
        WQLog(@"rename %@ -> %@", p.lastPathComponent, newName);
        return YES;
    }
    if (!WQDenied()) { WQSetError(error, WQErr()); return NO; }
    WQEnsure(WQParent(p), nil);
    if (rename(p.fileSystemRepresentation, dest.fileSystemRepresentation) != 0) {
        WQSetError(error, WQErr());
        return NO;
    }
    WQLog(@"rename %@ -> %@", p.lastPathComponent, newName);
    return YES;
}

BOOL WQCopyToLocal(NSString *src, NSString *dst, NSString **error)
{
    int fd = WQOpenRead(src, error);
    if (fd < 0) return NO;
    BOOL ok = WQStreamToLocal(fd, dst, error);
    close(fd);
    if (ok) WQLog(@"copied %@ -> %@", src, dst);
    return ok;
}

BOOL WQCopyFromLocal(NSString *src, NSString *dst, NSString **error)
{
    int in = open(WQNormalize(src).fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (in < 0) { WQSetError(error, WQErr()); return NO; }
    int out = WQOpenWrite(dst, O_WRONLY | O_CREAT | O_TRUNC, 0644, error);
    if (out < 0) { close(in); return NO; }

    uint8_t buffer[64 * 1024];
    BOOL ok = YES;
    for (;;) {
        ssize_t n = read(in, buffer, sizeof(buffer));
        if (n < 0) {
            if (errno == EINTR) continue;
            WQSetError(error, WQErr());
            ok = NO;
            break;
        }
        if (n == 0) break;
        if (!WQWriteAll(out, buffer, (size_t)n, error)) { ok = NO; break; }
    }
    close(in);
    if (!WQCloseChecked(out, error) && ok) ok = NO;
    if (!ok) unlink(WQNormalize(dst).fileSystemRepresentation);
    else WQLog(@"imported %@ -> %@", src, dst);
    return ok;
}

NSDictionary<NSString *, id> *WQStat(NSString *path, NSString **error)
{
    NSString *p = WQNormalize(path);
    struct stat st;
    if (lstat(p.fileSystemRepresentation, &st) != 0) {
        if (WQDenied()) {
            WQEnsure(WQParent(p), nil);
            if (lstat(p.fileSystemRepresentation, &st) != 0) { WQSetError(error, WQErr()); return nil; }
        } else { WQSetError(error, WQErr()); return nil; }
    }

    NSMutableDictionary *info = [@{
        @"路径": p,
        @"类型": S_ISDIR(st.st_mode) ? @"目录" :
                 S_ISLNK(st.st_mode) ? @"符号链接" :
                 S_ISREG(st.st_mode) ? @"普通文件" : @"其他",
        @"大小": WQFormatBytes((uint64_t)MAX(0, (int64_t)st.st_size)),
        @"inode": @((unsigned long long)st.st_ino),
        @"设备": @((unsigned long long)st.st_dev),
        @"权限": WQModeString(st.st_mode),
        @"链接数": @(st.st_nlink),
        @"UID/GID": [NSString stringWithFormat:@"%u / %u", st.st_uid, st.st_gid],
        @"修改时间": WQFormatDate(st.st_mtime),
        @"创建时间": WQFormatDate(st.st_birthtimespec.tv_sec),
    } mutableCopy];

    NSString *identifier = WQContainerIdentifier(p);
    if (identifier) info[@"容器 Bundle ID"] = identifier;

    char xattrNames[4096];
    ssize_t namesLength = listxattr(p.fileSystemRepresentation, xattrNames, sizeof(xattrNames) - 1, 0);
    if (namesLength > 0) {
        xattrNames[namesLength] = '\0';
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (char *cursor = xattrNames; cursor < xattrNames + namesLength; cursor += strlen(cursor) + 1) {
            NSString *name = [NSString stringWithUTF8String:cursor];
            if (name) [names addObject:name];
        }
        if (names.count) info[@"扩展属性"] = [names componentsJoinedByString:@"\n"];
    }
    return info.copy;
}

#pragma mark - Formatting

NSString *WQFormatBytes(uint64_t bytes)
{
    static const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    double value = (double)bytes;
    NSUInteger index = 0;
    while (value >= 1024.0 && index < 4) { value /= 1024.0; index++; }
    if (index == 0) return [NSString stringWithFormat:@"%llu B", (unsigned long long)bytes];
    return [NSString stringWithFormat:@"%.2f %s", value, units[index]];
}

NSString *WQFormatDate(time_t t)
{
    if (t <= 0) return @"-";
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]] ?: @"-";
}

NSString *WQModeString(mode_t mode)
{
    const char *types = "?pc?d?b?-?l?s???";
    char buffer[11] = {0};
    int t = (mode & S_IFMT) >> 12;
    buffer[0] = (t >= 0 && t < 16 && types[t]) ? types[t] : '?';
    const mode_t bits[9] = {S_IRUSR, S_IWUSR, S_IXUSR,
                            S_IRGRP, S_IWGRP, S_IXGRP,
                            S_IROTH, S_IWOTH, S_IXOTH};
    const char letters[9] = {'r', 'w', 'x', 'r', 'w', 'x', 'r', 'w', 'x'};
    for (int i = 0; i < 9; i++) buffer[i + 1] = (mode & bits[i]) ? letters[i] : '-';
    return [NSString stringWithUTF8String:buffer] ?: @"??????????";
}

NSString *WQHexDump(NSData *data, NSUInteger maxBytes)
{
    NSUInteger length = MIN(data.length, maxBytes ?: 16 * 1024);
    const uint8_t *bytes = data.bytes;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"总长度 %lu 字节，显示前 %lu 字节\n\n",
                       (unsigned long)data.length, (unsigned long)length];
    for (NSUInteger offset = 0; offset < length; offset += 16) {
        [out appendFormat:@"%08llx  ", (unsigned long long)offset];
        NSMutableString *ascii = [NSMutableString string];
        for (NSUInteger i = 0; i < 16; i++) {
            if (offset + i < length) {
                uint8_t b = bytes[offset + i];
                [out appendFormat:@"%02x ", b];
                [ascii appendFormat:@"%c", (b >= 32 && b < 127) ? b : '.'];
            } else {
                [out appendString:@"   "];
            }
            if (i == 7) [out appendString:@" "];
        }
        [out appendFormat:@" |%@|\n", ascii];
    }
    if (data.length > length) [out appendFormat:@"\n... 还有 %lu 字节未显示", (unsigned long)(data.length - length)];
    return out;
}

NSString *WQTextPreview(NSData *data, NSUInteger maxBytes)
{
    NSUInteger length = MIN(data.length, maxBytes ?: 256 * 1024);
    NSData *slice = [data subdataWithRange:NSMakeRange(0, length)];
    const uint8_t *bytes = slice.bytes;
    BOOL binary = NO;
    for (NSUInteger i = 0; i < length; i++) {
        if (bytes[i] == 0) { binary = YES; break; }
    }
    NSString *text = [[NSString alloc] initWithData:slice encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:slice encoding:NSISOLatin1StringEncoding];
        binary = YES;
    }
    if (!text) text = @"(无法解码为文本)";
    if (binary) text = [@"[含二进制内容，以下为尽力解码]\n\n" stringByAppendingString:text];
    if (data.length > length) {
        text = [text stringByAppendingFormat:@"\n\n… 共 %lu 字节，仅显示前 %lu 字节",
                (unsigned long)data.length, (unsigned long)length];
    }
    return text;
}
