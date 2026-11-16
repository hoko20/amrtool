//
//  ContainersViewController.m
//  SandboxExplorer
//
//  Enumerates other apps' data containers with fsgetpath (worse_query / KAMUI
//  technique), resolves their bundle ids from the containermanager xattr, and
//  opens them in the file browser after acquiring a sandbox extension.
//

#import "WQUI.h"
#import "WQKit.h"
#import <stdatomic.h>

@interface WQScanFlag : NSObject {
@public
    _Atomic BOOL value;
}
@end
@implementation WQScanFlag
@end

@interface WQContainersViewController ()
@property (nonatomic, strong) WQScanFlag *flag;
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *labels;
@property (nonatomic) BOOL scanning;
@property (nonatomic) uint64_t done;
@property (nonatomic) uint64_t total;
@property (nonatomic) NSUInteger found;
@property (nonatomic, copy) NSString *parent;
@end

@implementation WQContainersViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"容器";
        _paths = @[];
        _labels = [NSMutableDictionary dictionary];
        _parent = @"/private/var/mobile/Containers/Data/Application";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"数据容器";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"快速扫描"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(toggleScan:)];
    [self buildHeader];
}

- (void)buildHeader
{
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 92)];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = @"fsgetpath 通过 APFS object id 反查路径，不受沙盒限制，因此能列出 UUID 命名的容器目录。完整扫描可能需要数分钟；快速扫描只覆盖前 30 万个 id。";
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];
    self.tableView.tableHeaderView = container;
}

- (void)setScanning:(BOOL)scanning
{
    _scanning = scanning;
    self.navigationItem.rightBarButtonItem.title = scanning ? @"停止" : @"快速扫描";
    [self.tableView reloadData];
}

- (void)toggleScan:(id)sender
{
    if (self.scanning) {
        WQScanFlag *currentFlag = self.flag;
        atomic_store(&currentFlag->value, YES);
        WQLog(@"扫描取消请求已发出");
    } else {
        [self startScan:NO];
    }
}

- (void)startScan:(BOOL)full
{
    if (self.scanning) return;
    if (!WQOS26OrLater()) {
        WQPresentAlert(self, @"系统版本不支持", @"容器访问需要 iOS 26.0 - 26.7.2 或 27.2。");
        return;
    }
    if (!WQAppGroupReady()) {
        WQPresentAlert(self, @"App Group 未就绪", @"无法签发 sandbox extension。请用包含 App Group 的描述文件重新签名安装。");
    }

    WQScanFlag *flag = [WQScanFlag new];
    atomic_store(&flag->value, NO);
    self.flag = flag;
    self.done = 0;
    self.total = full ? 0 : 300000;
    self.found = 0;
    self.scanning = YES;

    NSString *parent = self.parent;
    uint64_t bound = full ? 0 : 300000;
    __weak typeof(self) weakSelf = self;
    WQLog(@"开始扫描 %@（%@）", parent, full ? @"完整" : @"快速");

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray<NSString *> *result = WQEnumerateChildren(parent, bound,
            ^(uint64_t done, uint64_t total, NSUInteger found) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __strong typeof(weakSelf) strongSelf = weakSelf;
                    if (!strongSelf || !strongSelf.scanning) return;
                    strongSelf.done = done;
                    strongSelf.total = total;
                    strongSelf.found = found;
                    [strongSelf.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                                        withRowAnimation:UITableViewRowAnimationNone];
                });
            },
            ^BOOL {
                return atomic_load(&flag->value);
            });

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.scanning = NO;
            if (result) {
                strongSelf.paths = result;
                strongSelf.labels = [NSMutableDictionary dictionary];
                WQLog(@"扫描完成：%lu 个容器", (unsigned long)result.count);
                [strongSelf.tableView reloadData];
                if (result.count == 0) {
                    WQPresentAlert(strongSelf, @"没有找到容器",
                        @"可以试试「完整扫描」，或换一个容器父目录；也可能是当前系统版本已封堵该技术。");
                }
            } else {
                WQPresentAlert(strongSelf, @"扫描已取消", @"已保留上一次的扫描结果。");
            }
        });
    });
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 3;
    if (section == 1) return self.scanning ? 1 : 0;
    return (NSInteger)self.paths.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section == 0) return @"扫描";
    if (section == 1) return self.scanning ? @"进度" : nil;
    return self.paths.count ? [NSString stringWithFormat:@"容器（%lu）", (unsigned long)self.paths.count] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return [NSString stringWithFormat:@"当前父目录：%@", self.parent];
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Cell"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section == 0) {
        NSArray *titles = @[@"快速扫描（前 30 万 id）", @"完整扫描（自动探测上限）", @"选择父目录 / 手动输入路径"];
        NSArray *subtitles = @[@"通常几十秒内完成", @"覆盖设备上所有已安装 App，可能数分钟", @"也可直接打开任意绝对路径"];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = subtitles[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        double percent = self.total ? (double)self.done / (double)self.total * 100.0 : 0;
        cell.textLabel.text = [NSString stringWithFormat:@"扫描中… %.1f%%", percent];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"已检查 %llu / %llu 个 id，命中 %lu 个目录",
                                     (unsigned long long)self.done, (unsigned long long)self.total,
                                     (unsigned long)self.found];
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else {
        NSString *path = self.paths[indexPath.row];
        NSString *label = self.labels[path];
        cell.textLabel.text = label ?: path.lastPathComponent;
        cell.detailTextLabel.text = path;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        if (!label) [self resolveLabelForPath:path indexPath:indexPath];
    }
    return cell;
}

- (void)resolveLabelForPath:(NSString *)path indexPath:(NSIndexPath *)indexPath
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSString *identifier = WQContainerIdentifier(path);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.labels[path] = identifier ?: path.lastPathComponent;
            [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath]
                                       withRowAnimation:UITableViewRowAnimationNone];
        });
    });
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self startScan:NO];
        else if (indexPath.row == 1) [self startScan:YES];
        else [self chooseParent];
        return;
    }
    if (indexPath.section == 1) return;

    NSString *path = self.paths[indexPath.row];
    [self openContainer:path];
}

- (void)chooseParent
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"容器位置"
                                                                  message:self.parent
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString *candidate in WQDefaultContainerParents()) {
        [sheet addAction:[UIAlertAction actionWithTitle:candidate style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            self.parent = candidate;
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"手动输入绝对路径并打开" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIAlertController *input = WQInputAlert(@"打开路径", @"输入一个已存在的目录或文件路径", @"/private/var/...", self.parent, ^(NSString *value) {
            if (value.length) [self openContainer:WQNormalize(value)];
        });
        [self presentViewController:input animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openContainer:(NSString *)path
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        NSString *error = nil;
        BOOL ok = WQEnsure(path, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) { WQPresentAlert(strongSelf, @"无法访问该容器", error ?: @"未知错误"); return; }
            WQBrowserViewController *browser = [[WQBrowserViewController alloc] initWithPath:path
                                                                                      title:path.lastPathComponent];
            [strongSelf.navigationController pushViewController:browser animated:YES];
        });
    });
}

@end
