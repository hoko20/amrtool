//
//  AFFilesViewController.m
//  AudioForge
//
//  输出文件列表：系统表格 + 原生左滑（分享 / 重命名 / 删除）。
//

#import "AFUI.h"
#import <math.h>

@interface AFFilesViewController ()
@property (nonatomic, copy) NSArray<NSString *> *files;
@property (nonatomic) CGFloat lastHeaderWidth;

- (void)reloadFiles;
- (void)refreshHeader;
- (void)shareFileAtIndex:(NSInteger)index fromCell:(UIView *)cell;
- (void)deleteFileAtIndex:(NSInteger)index;
- (void)renameFileAtIndex:(NSInteger)index;
@end

@implementation AFFilesViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"文件";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"输出文件";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    [self refreshHeader];
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

- (void)refreshHeader
{
    self.lastHeaderWidth = self.tableView.bounds.size.width;
    AFSetTableHeaderText(self.tableView,
                         [NSString stringWithFormat:@"输出目录\n%@", AFDocumentsPath()]);
}

- (void)reloadFiles
{
    self.files = AFOutputFileNames();
    [self.tableView reloadData];

    if (self.files.count == 0) {
        UILabel *label = [UILabel new];
        label.text = @"还没有输出文件\n在「转换」页导入音频后会自动出现在这里";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        label.textColor = UIColor.secondaryLabelColor;
        self.tableView.backgroundView = label;
    } else {
        self.tableView.backgroundView = nil;
    }
}

#pragma mark - 表格

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.files.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"左滑可分享、重命名或删除，点击行直接分享。文件保存在「文件」App → 我的 iPhone → AudioForge。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"Cell"];
    }

    NSString *name = self.files[indexPath.row];
    NSString *path = [AFDocumentsPath() stringByAppendingPathComponent:name];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *size = attributes[NSFileSize];
    NSDate *date = attributes[NSFileCreationDate] ?: [NSDate date];

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"MM-dd HH:mm";

    cell.textLabel.text = name;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                 [NSByteCountFormatter stringFromByteCount:size.longLongValue
                                                                countStyle:NSByteCountFormatterCountStyleFile],
                                 [formatter stringFromDate:date]];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.textLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self shareFileAtIndex:indexPath.row fromCell:[tableView cellForRowAtIndexPath:indexPath]];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
{
    __weak typeof(self) weakSelf = self;

    UIContextualAction *delete = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"删除"
                                                                       handler:^(UIContextualAction *action,
                                                                                 __kindof UIView *sourceView,
                                                                                 void (^completionHandler)(BOOL)) {
        [weakSelf deleteFileAtIndex:indexPath.row];
        completionHandler(YES);
    }];

    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                         title:@"重命名"
                                                                       handler:^(UIContextualAction *action,
                                                                                 __kindof UIView *sourceView,
                                                                                 void (^completionHandler)(BOOL)) {
        [weakSelf renameFileAtIndex:indexPath.row];
        completionHandler(YES);
    }];
    rename.backgroundColor = UIColor.systemOrangeColor;

    UIContextualAction *share = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal
                                                                        title:@"分享"
                                                                      handler:^(UIContextualAction *action,
                                                                                __kindof UIView *sourceView,
                                                                                void (^completionHandler)(BOOL)) {
        [weakSelf shareFileAtIndex:indexPath.row fromCell:(UITableViewCell *)sourceView];
        completionHandler(YES);
    }];
    share.backgroundColor = AFAccentColor();

    UISwipeActionsConfiguration *configuration =
        [UISwipeActionsConfiguration configurationWithActions:@[delete, rename, share]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

#pragma mark - 操作

- (void)shareFileAtIndex:(NSInteger)index fromCell:(UIView *)cell
{
    if (index < 0 || index >= (NSInteger)self.files.count) return;
    NSURL *url = [NSURL fileURLWithPath:[AFDocumentsPath() stringByAppendingPathComponent:self.files[index]]];

    UIActivityViewController *controller = [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                                             applicationActivities:nil];
    controller.popoverPresentationController.sourceView = cell ?: self.view;
    controller.popoverPresentationController.sourceRect = cell ? cell.bounds : self.view.bounds;
    [self presentViewController:controller animated:YES completion:nil];
}

- (void)deleteFileAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.files.count) return;
    NSString *path = [AFDocumentsPath() stringByAppendingPathComponent:self.files[index]];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [self reloadFiles];
}

- (void)renameFileAtIndex:(NSInteger)index
{
    if (index < 0 || index >= (NSInteger)self.files.count) return;

    NSString *name = self.files[index];
    NSString *base = name.stringByDeletingPathExtension;
    NSString *extension = name.pathExtension;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名"
                                                                  message:@"只修改文件名，扩展名保持不变"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = base;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        NSString *trimmed = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length == 0 || [trimmed isEqualToString:base]) return;

        NSString *directory = AFDocumentsPath();
        NSString *newBase = AFSanitizedBaseName(trimmed);
        NSString *target = [[directory stringByAppendingPathComponent:newBase]
                            stringByAppendingPathExtension:extension];
        if ([[NSFileManager defaultManager] fileExistsAtPath:target]) {
            AFPresentAlert(weakSelf, @"重命名失败", @"同名文件已存在");
            return;
        }
        NSError *error = nil;
        [[NSFileManager defaultManager] moveItemAtPath:[directory stringByAppendingPathComponent:name]
                                                toPath:target
                                                 error:&error];
        if (error) {
            AFPresentAlert(weakSelf, @"重命名失败", error.localizedDescription);
        }
        [weakSelf reloadFiles];
    }]];

    [self presentViewController:alert animated:YES completion:nil];
}

@end
