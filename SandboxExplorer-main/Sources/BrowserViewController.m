//
//  BrowserViewController.m
//  SandboxExplorer
//
//  Directory browser with read / write / create / rename / delete / import /
//  export. Every operation transparently acquires a sandbox extension through
//  WQFileOps when the sandbox denies a plain POSIX call.
//

#import "WQUI.h"
#import "WQKit.h"

@interface WQBrowserViewController () <UIDocumentPickerDelegate>
@property (nonatomic, copy) NSString *directory;
@property (nonatomic, copy) NSArray<WQItem *> *items;
@property (nonatomic, copy) NSString *loadError;
@end

@implementation WQBrowserViewController

- (instancetype)initWithPath:(NSString *)path title:(NSString *)title
{
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _directory = WQNormalize(path);
        _items = @[];
        self.title = title.length ? title : path.lastPathComponent;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(showCreateMenu:)];
    [self buildHeader];

    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reload];
}

- (void)buildHeader
{
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 62)];
    container.backgroundColor = UIColor.secondarySystemBackgroundColor;
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 2;
    label.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    label.textColor = UIColor.secondaryLabelColor;
    label.text = [NSString stringWithFormat:@"%@\n（点击复制路径）", self.directory];
    label.userInteractionEnabled = YES;
    [label addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self
                                                                      action:@selector(copyPath:)]];
    [container addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8],
    ]];
    self.tableView.tableHeaderView = container;
}

- (void)copyPath:(id)sender
{
    WQCopyToPasteboard(self.directory);
    WQPresentAlert(self, @"已复制", self.directory);
}

#pragma mark - Loading

- (void)reload
{
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *error = nil;
        NSString *directory = strongSelf.directory;
        WQEnsure(directory, nil);
        NSArray<WQItem *> *items = WQList(directory, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.items = items ?: @[];
            strongSelf.loadError = items ? nil : (error ?: @"无法读取目录");
            [strongSelf.tableView reloadData];
            [strongSelf.refreshControl endRefreshing];
            if (!items) WQLog(@"list %@ failed: %@", strongSelf.directory, strongSelf.loadError);
        });
    });
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (self.loadError) return self.loadError;
    if (self.items.count == 0) return @"目录为空，或当前尚未获得该目录的访问权限。";
    return [NSString stringWithFormat:@"%lu 个项目 · 已持有 %lu 个沙盒扩展",
            (unsigned long)self.items.count, (unsigned long)WQGrantCount()];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Item"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Item"];
    WQItem *item = self.items[indexPath.row];
    cell.textLabel.text = item.name;
    cell.textLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:item.directory ? @"folder.fill" :
                                                     item.symbolicLink ? @"link" : @"doc"];
    cell.imageView.tintColor = item.directory ? UIColor.systemOrangeColor : UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  ·  %@  ·  %@  ·  %@",
                                 item.directory ? @"目录" : WQFormatBytes(item.size),
                                 WQModeString(item.mode),
                                 WQFormatDate(item.mtime),
                                 [NSString stringWithFormat:@"ino %llu", (unsigned long long)item.inode]];
    cell.accessoryType = item.directory ? UITableViewCellAccessoryDisclosureIndicator
                                        : UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    WQItem *item = self.items[indexPath.row];
    if (item.directory) {
        WQBrowserViewController *next = [[WQBrowserViewController alloc] initWithPath:item.path
                                                                               title:item.name];
        [self.navigationController pushViewController:next animated:YES];
    } else {
        [self showFileMenu:item cell:[tableView cellForRowAtIndexPath:indexPath]];
    }
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
    [self showFileMenu:self.items[indexPath.row]
                  cell:[tableView cellForRowAtIndexPath:indexPath]];
}

#pragma mark - File menu

- (void)showFileMenu:(WQItem *)item cell:(UITableViewCell *)cell
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:item.name
                                                                  message:item.path
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;

    [sheet addAction:[UIAlertAction actionWithTitle:@"文本查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf previewText:item hexadecimal:NO];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"十六进制查看" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf previewText:item hexadecimal:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑并写入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf editFile:item];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"查看属性 / xattr" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf showAttributes:item];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"另存到「我的导出」" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf exportItem:item share:NO cell:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf exportItem:item share:YES cell:cell];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *input = WQInputAlert(@"重命名", item.path, @"新名称", item.name, ^(NSString *value) {
            if (!value.length) return;
            NSString *error = nil;
            BOOL ok = WQRename(item.path, value, &error);
            if (!ok) WQPresentAlert(weakSelf, @"重命名失败", error ?: @"未知错误");
            [weakSelf reload];
        });
        [weakSelf presentViewController:input animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"确认删除"
                                                                        message:item.path
                                                                 preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            NSString *error = nil;
            BOOL ok = WQDelete(item.path, &error);
            if (!ok) WQPresentAlert(weakSelf, @"删除失败", error ?: @"未知错误");
            [weakSelf reload];
        }]];
        [weakSelf presentViewController:confirm animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)previewText:(WQItem *)item hexadecimal:(BOOL)hex
{
    NSString *error = nil;
    NSData *data = WQRead(item.path, hex ? 64 * 1024 : 256 * 1024, &error);
    if (!data) { WQPresentAlert(self, @"读取失败", error ?: @"未知错误"); return; }
    NSString *text = hex ? WQHexDump(data, 16 * 1024) : WQTextPreview(data, 256 * 1024);
    WQTextViewController *viewer = [[WQTextViewController alloc]
        initWithTitle:[item.name stringByAppendingString:hex ? @" · HEX" : @" · 文本"]
                 text:text editable:NO save:nil];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)editFile:(WQItem *)item
{
    NSString *error = nil;
    NSData *data = WQRead(item.path, 2 * 1024 * 1024, &error);
    if (!data) { WQPresentAlert(self, @"读取失败", error ?: @"未知错误"); return; }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        WQPresentAlert(self, @"不是 UTF-8 文本", @"该文件无法按 UTF-8 解码，请改用「十六进制查看」，避免写入破坏二进制内容。");
        return;
    }
    if (item.size > 2 * 1024 * 1024) {
        WQPresentAlert(self, @"文件过大", @"编辑器只载入前 2 MB，保存会截断文件。请改用「另存到我的导出」后在外部编辑。");
        return;
    }
    __weak typeof(self) weakSelf = self;
    NSString *filePath = item.path;
    WQEditorSaveBlock save = ^(NSString *newText, void (^completion)(BOOL, NSString *)) {
        NSString *writeError = nil;
        BOOL ok = WQWrite(filePath, [newText dataUsingEncoding:NSUTF8StringEncoding], &writeError);
        completion(ok, ok ? @"写入成功（保持原 inode）" : (writeError ?: @"写入失败"));
        [weakSelf reload];
    };
    WQTextViewController *editor = [[WQTextViewController alloc] initWithTitle:item.name
                                                                         text:text
                                                                     editable:YES
                                                                         save:save];
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)showAttributes:(WQItem *)item
{
    NSString *error = nil;
    NSDictionary *info = WQStat(item.path, &error);
    if (!info) { WQPresentAlert(self, @"读取失败", error ?: @"未知错误"); return; }
    NSMutableString *text = [NSMutableString string];
    for (NSString *key in info) [text appendFormat:@"%@：\n%@\n\n", key, info[key]];
    WQTextViewController *viewer = [[WQTextViewController alloc]
        initWithTitle:[item.name stringByAppendingString:@" · 属性"]
                 text:text editable:NO save:nil];
    [self.navigationController pushViewController:viewer animated:YES];
}

- (void)exportItem:(WQItem *)item share:(BOOL)share cell:(UITableViewCell *)cell
{
    NSString *name = item.name;
    NSString *dest = [WQExportsPath() stringByAppendingPathComponent:name];
    NSString *error = nil;
    BOOL ok = WQCopyToLocal(item.path, dest, &error);
    if (!ok) { WQPresentAlert(self, @"导出失败", error ?: @"未知错误"); return; }
    if (!share) {
        WQPresentAlert(self, @"已导出", [NSString stringWithFormat:@"文件已保存到\n%@\n可在「文件」App 的「我的 iPhone → %@ → Exports」中找到。",
                                        dest, NSBundle.mainBundle.infoDictionary[@"CFBundleDisplayName"] ?: @"SandboxExplorer"]);
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc]
        initWithActivityItems:@[[NSURL fileURLWithPath:dest]] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) activity.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:activity animated:YES completion:nil];
}

#pragma mark - Create / import

- (void)showCreateMenu:(id)sender
{
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"在此目录新建 / 导入"
                                                                  message:self.directory
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"新建文本文件" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *input = WQInputAlert(@"新建文件", @"输入文件名（含扩展名）", @"notes.txt", nil, ^(NSString *value) {
            if (!value.length || [value containsString:@"/"]) return;
            NSString *path = [weakSelf.directory stringByAppendingPathComponent:value];
            WQEditorSaveBlock save = ^(NSString *text, void (^completion)(BOOL, NSString *)) {
                NSString *error = nil;
                BOOL ok = WQCreateFile(path, [text dataUsingEncoding:NSUTF8StringEncoding], &error);
                completion(ok, ok ? @"文件已创建" : (error ?: @"创建失败"));
                [weakSelf reload];
            };
            WQTextViewController *editor = [[WQTextViewController alloc] initWithTitle:value
                                                                                 text:@""
                                                                             editable:YES
                                                                                 save:save];
            [weakSelf.navigationController pushViewController:editor animated:YES];
        });
        [weakSelf presentViewController:input animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"新建文件夹" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIAlertController *input = WQInputAlert(@"新建文件夹", @"输入名称", @"New Folder", nil, ^(NSString *value) {
            if (!value.length || [value containsString:@"/"]) return;
            NSString *path = [weakSelf.directory stringByAppendingPathComponent:value];
            NSString *error = nil;
            if (!WQCreateDir(path, &error)) WQPresentAlert(weakSelf, @"创建失败", error ?: @"未知错误");
            [weakSelf reload];
        });
        [weakSelf presentViewController:input animated:YES completion:nil];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"从「文件」App 导入" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf presentDocumentPicker];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"释放全部沙盒扩展" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        WQReleaseAllGrants();
        [weakSelf reload];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)presentDocumentPicker
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item"]
                                                             inMode:UIDocumentPickerModeImport];
#pragma clang diagnostic pop
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    NSURL *source = urls.firstObject;
    if (!source) return;
    BOOL scoped = [source startAccessingSecurityScopedResource];
    NSString *dest = [self.directory stringByAppendingPathComponent:source.lastPathComponent];
    NSString *error = nil;
    BOOL ok = WQCopyFromLocal(source.path, dest, &error);
    if (scoped) [source stopAccessingSecurityScopedResource];
    WQPresentAlert(self, ok ? @"导入成功" : @"导入失败", ok ? dest : (error ?: @"未知错误"));
    [self reload];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
