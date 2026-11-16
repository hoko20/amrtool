//
//  AFProfileViewController.m
//  AudioForge
//

#import "AFUI.h"

@implementation AFProfileViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"我的";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"我的";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 3;
    if (section == 1) return 3;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @[@"应用信息", @"开源组件", @"仓库"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return @"所有转换都在本机完成，不会上传任何音频文件。";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"Cell"];
    }
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.textColor = UIColor.labelColor;

    if (indexPath.section == 0) {
        NSArray<NSString *> *titles = @[@"版本", @"应用名称", @"适配系统"];
        NSDictionary *info = [NSBundle mainBundle].infoDictionary;
        NSString *version = [NSString stringWithFormat:@"%@ (%@)",
                             info[@"CFBundleShortVersionString"] ?: @"1.0",
                             info[@"CFBundleVersion"] ?: @"1"];
        NSArray<NSString *> *values = @[version, @"AudioForge", @"iOS 26 及以上"];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = values[indexPath.row];
    } else if (indexPath.section == 1) {
        NSArray<NSString *> *titles = @[@"opencore-amr", @"vo-amrwbenc", @"silk-v3-decoder"];
        NSArray<NSString *> *subtitles = @[@"AMR-NB 编码器", @"AMR-WB 编码器", @"SILK 编码器"];
        cell.textLabel.text = titles[indexPath.row];
        cell.detailTextLabel.text = subtitles[indexPath.row];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"github.com/hoko20/amrtool";
        cell.detailTextLabel.text = @"源码与构建脚本";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;

    NSString *urlString = nil;
    if (indexPath.section == 1) {
        NSArray<NSString *> *urls = @[@"https://sourceforge.net/projects/opencore-amr/",
                                      @"https://sourceforge.net/projects/opencore-amr/files/vo-amrwbenc/",
                                      @"https://github.com/kn007/silk-v3-decoder"];
        urlString = urls[indexPath.row];
    } else {
        urlString = @"https://github.com/hoko20/amrtool";
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end
