//
//  HomeViewController.m
//  SandboxExplorer
//
//  Shows THIS app's own sandbox (always readable/writable), the current
//  signing/App Group status, and shortcuts into the file browser.
//

#import "WQUI.h"
#import "WQKit.h"

@interface WQHomeViewController ()
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *sandboxRows;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *statusRows;
@end

@implementation WQHomeViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"沙盒";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"沙盒管家";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 62;
    [self buildHeader];
    [self rebuildRows];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(refresh:)];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self rebuildRows];
    [self.tableView reloadData];
}

- (void)buildHeader
{
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 116)];
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = [NSString stringWithFormat:
        @"当前 App 的沙盒目录无需任何扩展即可读写。\n访问其它 App 的数据容器依赖 worse_query 沙盒扩展技术（需要 iOS 26+ 与可用的 App Group）。\n运行系统：iOS %@",
        WQOSVersionString()];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],
    ]];
    self.tableView.tableHeaderView = container;
}

- (void)rebuildRows
{
    self.sandboxRows = @[
        @[@"Home（沙盒根）", WQHomePath()],
        @[@"Documents", WQDocumentsPath()],
        @[@"Library", WQLibraryPath()],
        @[@"Library/Caches", WQCachesPath()],
        @[@"tmp", WQTmpPath()],
        @[@"App Group 容器", [self appGroupPath] ?: @"（未配置 / 描述文件不含该 group）"],
    ];

    NSString *group = WQAppGroup() ?: @"不可用";
    NSString *entitled = WQEntitledGroups().count ? [WQEntitledGroups() componentsJoinedByString:@", "] : @"无";
    NSString *support = WQOS26OrLater() ? @"支持（iOS 26 / 27）" : @"不支持（需要 iOS 26+）";
    NSString *ready = WQAppGroupReady() ? @"就绪" : @"未就绪 — 容器访问将失败";

    self.statusRows = @[
        @[@"Bundle ID", WQBundleIdentifier()],
        @[@"签名的 App Groups", entitled],
        @[@"生效的 App Group", group],
        @[@"容器访问状态", ready],
        @[@"系统支持", support],
        @[@"已持有的扩展", [NSString stringWithFormat:@"%lu 个", (unsigned long)WQGrantCount()]],
    ];
}

- (NSString *)appGroupPath
{
    NSString *group = WQAppGroup();
    if (!group) return nil;
    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group].path;
}

- (void)refresh:(id)sender
{
    [self rebuildRows];
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return (NSInteger)self.sandboxRows.count;
    if (section == 1) return (NSInteger)self.statusRows.count;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"当前 App 沙盒目录", @"运行状态", @"快捷操作"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) return @"点击任一条目可打开目录、复制路径或查看文件属性。";
    if (section == 1) return @"App Group 必须由签名用的描述文件包含，否则 containerURLForSecurityApplicationGroupIdentifier: 返回 nil。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Cell"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    if (indexPath.section < 2) {
        NSArray<NSString *> *row = (indexPath.section == 0 ? self.sandboxRows : self.statusRows)[indexPath.row];
        cell.textLabel.text = row[0];
        cell.detailTextLabel.text = row[1];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        NSArray<NSString *> *titles = @[@"在 Documents 写入示例文件", @"打开我的 Documents", @"扫描其它 App 容器", @"清空诊断日志"];
        NSArray<NSString *> *subtitles = @[
            @"验证沙盒内读写权限",
            @"浏览 / 新建 / 编辑 / 删除文件",
            @"worse_query + fsgetpath 枚举",
            @"清除本次运行的日志缓冲",
        ];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = subtitles[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

    if (indexPath.section == 0) {
        NSArray<NSString *> *row = self.sandboxRows[indexPath.row];
        [self showPathActions:row[0] path:row[1] cell:cell];
    } else if (indexPath.section == 1) {
        NSArray<NSString *> *row = self.statusRows[indexPath.row];
        WQCopyToPasteboard(row[1]);
        WQPresentAlert(self, @"已复制", row[1]);
    } else {
        switch (indexPath.row) {
            case 0: [self writeDemo]; break;
            case 1: [self openBrowser:WQDocumentsPath() title:@"Documents"]; break;
            case 2: [self.tabBarController setSelectedIndex:1]; break;
            case 3: WQLogClear(); WQLog(@"日志已清空"); WQPresentAlert(self, @"完成", @"诊断日志已清空"); break;
            default: break;
        }
    }
}

#pragma mark - Actions

- (void)showPathActions:(NSString *)name path:(NSString *)path cell:(UITableViewCell *)cell
{
    if ([path hasPrefix:@"（"]) {
        WQPresentAlert(self, @"App Group 不可用", @"请在签名用的描述文件中启用 com.apple.security.application-groups，并使用相同的 group id 重新构建。");
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name
                                                                  message:path
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"打开此目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self openBrowser:path title:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        WQCopyToPasteboard(path);
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看属性" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showAttributes:path title:name];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openBrowser:(NSString *)path title:(NSString *)title
{
    WQBrowserViewController *browser = [[WQBrowserViewController alloc] initWithPath:path title:title];
    [self.navigationController pushViewController:browser animated:YES];
}

- (void)showAttributes:(NSString *)path title:(NSString *)title
{
    NSString *error = nil;
    NSDictionary *info = WQStat(path, &error);
    if (!info) { WQPresentAlert(self, @"读取失败", error ?: @"未知错误"); return; }
    NSMutableString *text = [NSMutableString string];
    for (NSString *key in info) [text appendFormat:@"%@：\n%@\n\n", key, info[key]];
    WQTextViewController *viewer = [[WQTextViewController alloc] initWithTitle:[title stringByAppendingString:@" · 属性"]
                                                                         text:text
                                                                     editable:NO
                                                                         save:nil];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)writeDemo
{
    NSString *path = [WQDocumentsPath() stringByAppendingPathComponent:@"sandbox-demo.txt"];
    NSString *content = [NSString stringWithFormat:
        @"SandboxExplorer 写入测试\n时间：%@\nBundle ID：%@\nHome：%@\nDocuments：%@\n",
        [NSDate date], WQBundleIdentifier(), WQHomePath(), WQDocumentsPath()];
    NSString *error = nil;
    BOOL ok = WQWrite(path, [content dataUsingEncoding:NSUTF8StringEncoding], &error);
    if (!ok) {
        // File may not exist yet on a fresh install.
        ok = WQCreateFile(path, [content dataUsingEncoding:NSUTF8StringEncoding], &error);
    }
    WQPresentAlert(self, ok ? @"写入成功" : @"写入失败", ok ? path : (error ?: @"未知错误"));
}

@end
