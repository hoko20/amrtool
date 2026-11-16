//
//  WQKit.h
//  SandboxExplorer
//
//  Public surface of the filesystem layer.
//
//  The sandbox-extension technique implemented in WQBridge.m is derived from
//  worse_query by Taj C (forcequitOS), https://github.com/forcequitOS/worse_query
//  (GPL-3.0-or-later). Container enumeration in WQPathLeak.m uses the same
//  fsgetpath approach published there and in WQFiles / KAMUI. This project is
//  distributed under GPL-3.0-or-later; see LICENSE and THIRD_PARTY_NOTICES.md.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Diagnostics log

void WQLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
NSString *WQLogText(void);
void WQLogClear(void);

#pragma mark - This app's own sandbox

NSString *WQHomePath(void);
NSString *WQDocumentsPath(void);
NSString *WQLibraryPath(void);
NSString *WQCachesPath(void);
NSString *WQTmpPath(void);
NSString *WQExportsPath(void);
NSString *WQBundleIdentifier(void);
NSString *WQOSVersionString(void);
NSInteger WQOSMajorVersion(void);
BOOL WQOS26OrLater(void);
BOOL WQOS27OrLater(void);

#pragma mark - worse_query bridge

/// App Group ids actually present in the signed entitlements.
NSArray<NSString *> *WQEntitledGroups(void);
/// The first entitled group whose container URL resolves. Nil = unusable.
NSString *_Nullable WQAppGroup(void);
BOOL WQAppGroupReady(void);

/// Obtain (or reuse) a sandbox extension covering `path`.
/// Returns the extension handle (>= 0) or a negative WQBridge error code.
int64_t WQGrant(NSString *path);
/// Convenience: grant + verify the path really became openable.
BOOL WQEnsure(NSString *path, NSString *_Nullable *_Nullable error);
/// Raw one-shot query, for the tools console. Caller owns the returned handle.
int64_t WQQueryRaw(NSString *path, BOOL altFlags, BOOL createDir);
void WQReleaseHandle(int64_t handle);
void WQReleaseAllGrants(void);
NSUInteger WQGrantCount(void);
NSArray<NSString *> *WQGrantPaths(void);
NSString *WQGrantErrorText(int64_t code);

#pragma mark - Container discovery

/// Rough newest object id on the data volume (probe file + safety margin).
uint64_t WQProbeMaxInode(void);
/// Brute-force direct children of `parent` with fsgetpath. Runs on a parallel
/// dispatch queue; `cancelled` is polled and stops the scan early.
NSArray<NSString *> *_Nullable WQEnumerateChildren(
    NSString *parent,
    uint64_t maxInode,
    void (^_Nullable progress)(uint64_t done, uint64_t total, NSUInteger found),
    BOOL (^_Nullable cancelled)(void));
/// com.apple.containermanager.identifier xattr of a container directory.
NSString *_Nullable WQContainerIdentifier(NSString *path);
NSArray<NSString *> *WQDefaultContainerParents(void);

#pragma mark - File operations (all auto-grant on sandbox denial)

@interface WQItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *path;
@property (nonatomic) BOOL directory;
@property (nonatomic) BOOL symbolicLink;
@property (nonatomic) uint64_t size;
@property (nonatomic) uint64_t inode;
@property (nonatomic) mode_t mode;
@property (nonatomic) time_t mtime;
@end

NSArray<WQItem *> *_Nullable WQList(NSString *dir, NSString *_Nullable *_Nullable error);
NSData *_Nullable WQRead(NSString *path, NSUInteger maxBytes, NSString *_Nullable *_Nullable error);
BOOL WQWrite(NSString *path, NSData *data, NSString *_Nullable *_Nullable error);
BOOL WQCreateFile(NSString *path, NSData *data, NSString *_Nullable *_Nullable error);
BOOL WQCreateDir(NSString *path, NSString *_Nullable *_Nullable error);
BOOL WQDelete(NSString *path, NSString *_Nullable *_Nullable error);
BOOL WQRename(NSString *path, NSString *newName, NSString *_Nullable *_Nullable error);
/// Copy an arbitrary (possibly external-container) file into this app's sandbox.
BOOL WQCopyToLocal(NSString *src, NSString *dst, NSString *_Nullable *_Nullable error);
/// Copy a local file into a target path (which may live in another container).
BOOL WQCopyFromLocal(NSString *src, NSString *dst, NSString *_Nullable *_Nullable error);
NSDictionary<NSString *, id> *_Nullable WQStat(NSString *path, NSString *_Nullable *_Nullable error);

#pragma mark - Formatting helpers

NSString *WQNormalize(NSString *path);
NSString *WQFormatBytes(uint64_t bytes);
NSString *WQFormatDate(time_t t);
NSString *WQModeString(mode_t mode);
NSString *WQHexDump(NSData *data, NSUInteger maxBytes);
NSString *WQTextPreview(NSData *data, NSUInteger maxBytes);

NS_ASSUME_NONNULL_END
