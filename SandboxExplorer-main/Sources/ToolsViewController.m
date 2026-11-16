//
//  ToolsViewController.m
//  SandboxExplorer
//
//  Manual sandbox-extension console, held-token inspector, diagnostic log and
//  the GPL / upstream attribution panel.
//

#import "WQUI.h"
#import "WQKit.h"

static BOOL WQAutoAltFlags(void)
{
    // iOS 26 AppGroup containers need the alternative query flags; iOS 27+
    // uses the standard set. WQGrant also falls back to the other set.
    return !WQOS27OrLater();
}

@interface WQToolsViewController ()
@property (nonatomic) int64_t manualHandle;
@property (nonatomic, copy) NSString *manualPath;
@property (nonatomic, copy) NSArray<NSString *> *grantPaths;
@end

@implementation WQToolsViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"工具";
        _manualHandle = -255;
        _manualPath = @"/private/var/mobile/Containers/Shared/AppGroup/";
        _grantPaths = @[];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"扩展 / 日志";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.grantPaths = WQGrantPaths();
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 6;
    if (section == 1) return (NSInteger)self.grantPaths.count + 1;
    if (section == 2) return 4;
    return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"手动获取沙盒扩展", @"当前持有的扩展", @"诊断日志", @"关于 / 许可"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return @"iOS 26 的 AppGroup 路径通常需要 alternative flags；自动模式会依次尝试两种 flags 并记住可用的那一组。";
    if (section == 1) return @"内核对单个进程可持有的扩展数量有限制，缓存上限 192 个，超出后按 LRU 释放。";
    if (section == 3) return @"本工程基于 GPL-3.0-or-later 代码，分发时须保留上游声明与相同许可证。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Cell"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0:
                cell.textLabel.text = @"目标路径（点击修改）";
                cell.detailTextLabel.text = self.manualPath;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                break;
            case 1:
                cell.textLabel.text = self.manualHandle >= 0
                    ? [NSString stringWithFormat:@"已持有 handle = %lld", (long long)self.manualHandle]
                    : @"未持有手动扩展";
                cell.detailTextLabel.text = self.manualHandle < 0
                    ? WQGrantErrorText(self.manualHandle) : @"使用完请释放，避免占满内核配额";
                break;
            case 2: cell.textLabel.text = @"消费扩展（自动 flags）"; cell.detailTextLabel.text = @"按系统版本选择并自动回退"; break;
            case 3: cell.textLabel.text = @"消费扩展（alt flags）"; cell.detailTextLabel.text = @"0x0000000800000000"; break;
            case 4: cell.textLabel.text = @"消费扩展（标准 flags）"; cell.detailTextLabel.text = @"0x0000008000000000"; break;
            case 5: cell.textLabel.text = @"释放手动扩展"; cell.detailTextLabel.text = @"sandbox_extension_release"; break;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == (NSInteger)self.grantPaths.count) {
            cell.textLabel.text = @"释放全部扩展";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"共 %lu 个", (unsigned long)self.grantPaths.count];
        } else {
            cell.textLabel.text = self.grantPaths[indexPath.row].lastPathComponent;
            cell.detailTextLabel.text = self.grantPaths[indexPath.row];
        }
    } else if (indexPath.section == 2) {
        NSArray *titles = @[@"查看完整日志", @"复制日志", @"导出 / 分享日志", @"清空日志"];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"当前缓冲 %lu 字符", (unsigned long)WQLogText().length];
    } else {
        NSArray *titles = @[@"技术与上游声明", @"github.com/forcequitOS/worse_query", @"github.com/hseons/WQManager"];
        NSArray *subs = @[@"GPL-3.0-or-later · 沙盒扩展技术与架构参考",
                          @"Taj C (forcequit) · sandbox extension PoC · 在浏览器打开",
                          @"hseons · App 数据管理器参考 · 在浏览器打开"];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = subs[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        switch (indexPath.row) {
            case 0: [self editManualPath]; break;
            case 2: [self consume:WQAutoAltFlags()]; break;
            case 3: [self consume:YES]; break;
            case 4: [self consume:NO]; break;
            case 5: [self releaseManual]; break;
            default: break;
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == (NSInteger)self.grantPaths.count) {
            WQReleaseAllGrants();
            self.grantPaths = WQGrantPaths();
            [self.tableView reloadData];
        } else {
            WQCopyToPasteboard(self.grantPaths[indexPath.row]);
        }
    } else if (indexPath.section == 2) {
        switch (indexPath.row) {
            case 0: [self showLog]; break;
            case 1: WQCopyToPasteboard(WQLogText()); WQPresentAlert(self, @"已复制", @"日志已复制到剪贴板"); break;
            case 2: [self shareLogFromCell:[tableView cellForRowAtIndexPath:indexPath]]; break;
            case 3: WQLogClear(); WQLog(@"日志已清空"); [self.tableView reloadData]; break;
        }
    } else {
        if (indexPath.row == 0) [self showCredits];
        else [self openURL:indexPath.row == 1 ? @"https://github.com/forcequitOS/worse_query"
                                              : @"https://github.com/hseons/WQManager"];
    }
}

#pragma mark - Actions

- (void)editManualPath
{
    UIAlertController *input = WQInputAlert(@"目标路径", @"必须是一个已存在的路径", @"/private/var/...", self.manualPath, ^(NSString *value) {
        if (!value.length) return;
        self.manualPath = WQNormalize(value);
        [self.tableView reloadData];
    });
    [self presentViewController:input animated:YES completion:nil];
}

- (void)consume:(BOOL)altFlags
{
    if (self.manualHandle >= 0) {
        WQPresentAlert(self, @"已有手动扩展", @"请先释放当前 handle。");
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *path = strongSelf.manualPath;
        int64_t handle = WQQueryRaw(path, altFlags, NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) uiSelf = weakSelf;
            if (!uiSelf) return;
            uiSelf.manualHandle = handle;
            [uiSelf.tableView reloadData];
            if (handle < 0) {
                WQPresentAlert(uiSelf, @"获取失败", WQGrantErrorText(handle));
            } else {
                // Now that the extension is held, ordinary POSIX I/O works on the
                // target. Prove it by listing the directory when possible.
                NSString *error = nil;
                NSArray *items = WQList(uiSelf.manualPath, &error);
                WQPresentAlert(uiSelf, @"获取成功",
                    [NSString stringWithFormat:@"handle = %lld\n目录条目：%@",
                     (long long)handle, items ? @(items.count) : (error ?: @"不可列目录")]);
            }
        });
    });
}

- (void)releaseManual
{
    if (self.manualHandle < 0) {
        WQPresentAlert(self, @"无可释放的扩展", @"先消费一个 sandbox extension。");
        return;
    }
    WQReleaseHandle(self.manualHandle);
    WQLog(@"released manual handle %lld", (long long)self.manualHandle);
    self.manualHandle = -255;
    [self.tableView reloadData];
}

- (void)showLog
{
    NSString *text = WQLogText();
    WQTextViewController *viewer = [[WQTextViewController alloc] initWithTitle:@"诊断日志"
                                                                         text:text.length ? text : @"（日志为空）"
                                                                     editable:NO
                                                                         save:nil];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)shareLogFromCell:(UITableViewCell *)cell
{
    NSString *dir = [WQDocumentsPath() stringByAppendingPathComponent:@"Logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *path = [dir stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"sandboxexplorer-%@.log", [fmt stringFromDate:NSDate.date]]];
    NSString *error = nil;
    BOOL ok = WQWrite(path, [WQLogText() dataUsingEncoding:NSUTF8StringEncoding], &error);
    if (!ok) ok = WQCreateFile(path, [WQLogText() dataUsingEncoding:NSUTF8StringEncoding], &error);
    if (!ok) { WQPresentAlert(self, @"导出失败", error ?: @"未知错误"); return; }

    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) activity.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)showCredits
{
    NSString *text =
        @"SandboxExplorer · 1.0\n\n"
        @"沙盒扩展技术（App Group Library/Caches 符号链接 + containermanagerd\n"
        @"container_query_* + sandbox_extension_consume）来自：\n"
        @"  worse_query — Taj C (forcequitOS)\n"
        @"  https://github.com/forcequitOS/worse_query\n"
        @"  GPL-3.0-or-later\n\n"
        @"容器枚举、路径安全与产品形态参考：\n"
        @"  WQManager — hseons\n"
        @"  https://github.com/hseons/WQManager\n"
        @"  GPL-3.0-or-later\n\n"
        @"fsgetpath 枚举思路参考 KAMUI (murk-sus) 与 WQFiles (kolbicz)。\n\n"
        @"本工程为独立重写实现，采用 GPL-3.0-or-later 许可证。分发任何衍生作品时\n"
        @"必须保留上述声明并继续使用相同许可证。\n\n"
        @"注意：容器读写会直接改动目标 App 的数据，操作前请自行确认。";
    WQTextViewController *viewer = [[WQTextViewController alloc] initWithTitle:@"技术与上游声明"
                                                                         text:text
                                                                     editable:NO
                                                                         save:nil];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)openURL:(NSString *)string
{
    NSURL *url = [NSURL URLWithString:string];
    if (!url || ![UIApplication.sharedApplication canOpenURL:url]) return;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

@end
