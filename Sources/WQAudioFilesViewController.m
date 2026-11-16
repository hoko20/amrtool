//
//  WQAudioFilesViewController.m
//  SandboxExplorer
//

#import "WQAudio.h"
#import "WQKit.h"
#import "WQUI.h"
#import <math.h>

@interface WQAudioFilesViewController ()
@property (nonatomic, copy) NSArray<NSString *> *files;
@property (nonatomic) CGFloat lastHeaderWidth;
@end

@implementation WQAudioFilesViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"转换输出";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(refresh:)];
    [self refreshHeader];
    [self reloadFiles];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshHeader];
    [self reloadFiles];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width > 0 && fabs(width - self.lastHeaderWidth) > 0.5) {
        [self refreshHeader];
    }
}

- (void)refresh:(id)sender
{
    [self refreshHeader];
    [self reloadFiles];
}

- (void)refreshHeader
{
    self.lastHeaderWidth = self.tableView.bounds.size.width;
    WQAudioSetTableHeader(self.tableView,
                          [NSString stringWithFormat:@"输出目录\n%@", WQAudioOutputDirectory()]);
}

- (void)reloadFiles
{
    self.files = WQAudioOutputFiles();
    [self updateEmptyView];
    [self.tableView reloadData];
}

- (void)updateEmptyView
{
    if (self.files.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [UILabel new];
    label.text = @"还没有转换文件\n先在「转换」页导入音频";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    label.textColor = UIColor.secondaryLabelColor;
    self.tableView.backgroundView = label;
}

- (NSString *)pathAtIndex:(NSInteger)index
{
    return [WQAudioOutputDirectory() stringByAppendingPathComponent:self.files[index]];
}

- (NSDictionary *)attributesAtIndex:(NSInteger)index
{
    return [NSFileManager.defaultManager attributesOfItemAtPath:[self pathAtIndex:index] error:nil] ?: @{};
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (self.files.count == 0) return nil;
    uint64_t total = 0;
    for (NSInteger i = 0; i < (NSInteger)self.files.count; i++) {
        total += [self attributesAtIndex:i][NSFileSize].unsignedLongLongValue;
    }
    return [NSString stringWithFormat:@"共 %lu 个文件 · %@",
            (unsigned long)self.files.count, WQFormatBytes(total)];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Cell"];
    NSDictionary *attributes = [self attributesAtIndex:indexPath.row];
    cell.textLabel.text = self.files[indexPath.row];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
        WQFormatBytes([attributes[NSFileSize] unsignedLongLongValue]),
        WQFormatDate([attributes[NSFileModificationDate] timeIntervalSince1970])];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *name = self.files[indexPath.row];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:name
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"分享" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIActivityViewController *activity = [[UIActivityViewController alloc]
            initWithActivityItems:@[[NSURL fileURLWithPath:[self pathAtIndex:indexPath.row]]]
            applicationActivities:nil];
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        activity.popoverPresentationController.sourceView = cell ?: self.view;
        if (cell) activity.popoverPresentationController.sourceRect = cell.bounds;
        [self presentViewController:activity animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [self renameAtIndex:indexPath.row];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        [self deleteAtIndex:indexPath.row];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell ?: self.view;
    if (cell) sheet.popoverPresentationController.sourceRect = cell.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UIContextualAction *delete = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleDestructive
                            title:@"删除"
                          handler:^(UIContextualAction *action, UIView *source, void (^completion)(BOOL)) {
        [self deleteAtIndex:indexPath.row];
        completion(YES);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[delete]];
}

#pragma mark - Actions

- (void)renameAtIndex:(NSInteger)index
{
    NSString *name = self.files[index];
    NSString *extension = name.pathExtension;
    NSString *base = name.stringByDeletingPathExtension;
    UIAlertController *alert = WQInputAlert(@"重命名", @"扩展名保持不变", nil, base, ^(NSString *value) {
        NSString *newBase = WQAudioBaseName(value);
        if ([newBase isEqualToString:base]) return;

        NSString *target = [WQAudioOutputDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat:@"%@.%@", newBase, extension]];
        if ([NSFileManager.defaultManager fileExistsAtPath:target]) {
            WQPresentAlert(self, @"名称已存在", @"换一个名字试试。");
            return;
        }

        NSError *error = nil;
        BOOL ok = [NSFileManager.defaultManager moveItemAtPath:[self pathAtIndex:index]
                                                        toPath:target
                                                         error:&error];
        if (!ok) {
            WQPresentAlert(self, @"重命名失败", error.localizedDescription ?: @"请重试");
            return;
        }
        [self reloadFiles];
    });
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.files.count) return;
    NSString *path = [self pathAtIndex:index];
    NSError *error = nil;
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        WQPresentAlert(self, @"删除失败", error.localizedDescription ?: @"请重试");
        return;
    }
    [self reloadFiles];
}

@end
