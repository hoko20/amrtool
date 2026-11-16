//
//  AFToolsViewController.m
//  AudioForge
//

#import "AFUI.h"

@implementation AFToolsViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"工具";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"工具";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return section == 0 ? 2 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"文件与存储", @"编码说明"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return @"输出目录：本应用 Documents，可在「文件」App 的「我的 iPhone → AudioForge」中访问。";
    }
    return @"SILK 用于微信 / QQ，AMR 用于兼容性要求高的语音平台，M4A 用于需要高音质的场合。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"Cell"];
    }
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.textLabel.textColor = UIColor.labelColor;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"复制 Documents 路径";
            cell.detailTextLabel.text = AFDocumentsPath();
            cell.accessoryType = UITableViewCellAccessoryNone;
        } else {
            cell.textLabel.text = @"清空全部输出文件";
            cell.detailTextLabel.text = @"删除所有已转换的音频";
            cell.textLabel.textColor = UIColor.systemRedColor;
        }
    } else {
        cell.textLabel.text = @"四种输出格式的区别";
        cell.detailTextLabel.text = @"采样率、码率与适用场景";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            [UIPasteboard generalPasteboard].string = AFDocumentsPath();
            AFPresentAlert(self, @"已复制", AFDocumentsPath());
        } else {
            [self confirmClear];
        }
        return;
    }

    NSString *text =
        @"SILK · .aud（25 kbps / 24 kHz）\n"
        @"微信、QQ 语音条使用的编码。音质好、体积小，适合发语音；只认 AMR 的语音网关不支持。\n\n"
        @"AMR-NB（12.2 kbps / 8 kHz）\n"
        @"兼容性最好，几乎所有语音平台都能识别。8kHz 电话音质已经是 AMR-NB 的上限。\n\n"
        @"AMR-WB（23.85 kbps / 16 kHz）\n"
        @"AMR 家族的最高档，宽带语音，比 NB 明显清晰；个别老设备只接受 NB。\n\n"
        @"M4A · AAC（96 kbps）\n"
        @"接近原始音质，适合通用播放、分享与存档，但不是 AMR 格式。\n\n"
        @"体积参考：10 分钟音频，AMR-NB 约 0.9 MB，SILK 约 1.8 MB，M4A 约 7 MB。";

    AFTextViewController *controller = [[AFTextViewController alloc] initWithTitle:@"编码说明" text:text];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)confirmClear
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空全部输出文件？"
                                                                  message:@"操作不可撤销"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSArray<NSString *> *contents = [[NSFileManager defaultManager]
                                         contentsOfDirectoryAtPath:AFDocumentsPath() error:nil];
        NSSet<NSString *> *suffixes = [NSSet setWithObjects:@"amr", @"aud", @"m4a", nil];
        for (NSString *name in contents) {
            if ([suffixes containsObject:name.pathExtension.lowercaseString]) {
                NSString *path = [AFDocumentsPath() stringByAppendingPathComponent:name];
                [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            }
        }
        [weakSelf.tableView reloadData];
        AFPresentAlert(weakSelf, @"已清空", @"所有输出文件已删除");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
