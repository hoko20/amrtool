//
//  AFConvertViewController.m
//  AudioForge
//
//  转换页：导入音频/视频、选择输出格式、转换并进入输出文件列表。
//

#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "AFUI.h"
#import "AMREncoder.h"

@interface AFConvertViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic) AFOutputFormat format;
@property (nonatomic, getter=isBusy) BOOL busy;
@property (nonatomic) double progress;
@property (nonatomic, copy) NSString *currentName;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, copy) NSString *errorText;

- (void)startConversionWithURL:(NSURL *)url displayName:(NSString *)displayName;
- (AMROutputFormat)amrFormatFor:(AFOutputFormat)format;
- (BOOL)exportM4AFromURL:(NSURL *)input toURL:(NSURL *)output error:(NSError **)error;
- (NSURL *)temporaryCopyOfURL:(NSURL *)url error:(NSError **)error;
@end

@implementation AFConvertViewController

- (instancetype)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        self.title = @"转换";
        _format = AFCurrentFormat();
        _statusText = @"等待选择文件";
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"AudioForge";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - 分区

- (BOOL)showProgress
{
    return self.isBusy;
}

- (NSInteger)progressSection
{
    return 2;
}

- (NSInteger)outputSection
{
    return self.isBusy ? 3 : 2;
}

- (NSArray<NSString *> *)sectionTitles
{
    if (self.isBusy) {
        return @[@"导入", @"输出格式", @"进度", @"输出文件"];
    }
    return @[@"导入", @"输出格式", @"输出文件"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.isBusy ? 4 : 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) return 2;
    if (section == 1) return 3;
    if (self.isBusy && section == self.progressSection) return 1;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.sectionTitles[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == 0) {
        return self.errorText ?: [NSString stringWithFormat:@"支持 MP3、MP4、M4A、MOV、WAV 等常见音视频。当前状态：%@", self.statusText];
    }
    if (section == 1) {
        return AFFormatSummary(self.format);
    }
    if (section == self.outputSection) {
        return @"转换结果保存在本应用的 Documents 目录，可在「文件」App 中查看和导出。";
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section
{
    UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
    footer.textLabel.textColor = (section == 0 && self.errorText)
        ? UIColor.systemRedColor
        : UIColor.secondaryLabelColor;
}

#pragma mark - 单元格

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.isBusy && indexPath.section == self.progressSection) {
        return [self progressCellForTableView:tableView];
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"Cell"];
    }
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"从「文件」选择音频或视频";
            cell.detailTextLabel.text = @"MP3 / MP4 / M4A / MOV / WAV";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            cell.textLabel.text = @"从相册选择视频";
            cell.detailTextLabel.text = @"自动只取视频中的声音";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.textLabel.textColor = self.isBusy ? UIColor.secondaryLabelColor : UIColor.labelColor;
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"输出格式";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                         AFFormatTitle(self.format), AFFormatSubtitle(self.format)];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"采样率";
            cell.detailTextLabel.text = [self sampleRateText];
        } else {
            cell.textLabel.text = @"码率";
            cell.detailTextLabel.text = [self bitrateText];
        }
    } else {
        NSInteger count = (NSInteger)AFOutputFileNames().count;
        cell.textLabel.text = @"输出文件";
        cell.detailTextLabel.text = count == 0
            ? @"还没有文件"
            : [NSString stringWithFormat:@"%ld 个文件 · 点击查看", (long)count];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (NSString *)sampleRateText
{
    switch (self.format) {
        case AFOutputFormatSilk: return @"24 kHz";
        case AFOutputFormatNB:   return @"8 kHz";
        case AFOutputFormatWB:   return @"16 kHz";
        case AFOutputFormatM4A:  return @"跟随源文件";
    }
}

- (NSString *)bitrateText
{
    switch (self.format) {
        case AFOutputFormatSilk: return @"25 kbps 单声道";
        case AFOutputFormatNB:   return @"12.2 kbps 单声道";
        case AFOutputFormatWB:   return @"23.85 kbps 单声道";
        case AFOutputFormatM4A:  return @"AAC 96 kbps";
    }
}

- (UITableViewCell *)progressCellForTableView:(UITableView *)tableView
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ProgressCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:@"ProgressCell"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        UILabel *name = [UILabel new];
        name.tag = 102;
        name.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        name.lineBreakMode = NSLineBreakByTruncatingMiddle;
        name.translatesAutoresizingMaskIntoConstraints = NO;

        UILabel *percent = [UILabel new];
        percent.tag = 103;
        percent.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        percent.textColor = UIColor.secondaryLabelColor;
        percent.textAlignment = NSTextAlignmentRight;
        percent.translatesAutoresizingMaskIntoConstraints = NO;

        UIProgressView *bar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        bar.tag = 101;
        bar.progressTintColor = AFAccentColor();
        bar.translatesAutoresizingMaskIntoConstraints = NO;

        [cell.contentView addSubview:name];
        [cell.contentView addSubview:percent];
        [cell.contentView addSubview:bar];

        [NSLayoutConstraint activateConstraints:@[
            [name.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [name.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:10],
            [percent.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [percent.firstBaselineAnchor constraintEqualToAnchor:name.firstBaselineAnchor],
            [percent.leadingAnchor constraintGreaterThanOrEqualToAnchor:name.trailingAnchor constant:8],
            [bar.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
            [bar.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
            [bar.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:8],
            [bar.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
        ]];
    }

    UILabel *name = (UILabel *)[cell.contentView viewWithTag:102];
    UILabel *percent = (UILabel *)[cell.contentView viewWithTag:103];
    UIProgressView *bar = (UIProgressView *)[cell.contentView viewWithTag:101];
    name.text = self.currentName.length ? self.currentName : @"正在转换";
    percent.text = [NSString stringWithFormat:@"%.0f%%", self.progress * 100];
    bar.progress = (float)self.progress;
    return cell;
}

- (void)refreshProgressCell
{
    if (!self.isBusy) return;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:self.progressSection];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    if (!cell) return;
    UILabel *percent = (UILabel *)[cell.contentView viewWithTag:103];
    UIProgressView *bar = (UIProgressView *)[cell.contentView viewWithTag:101];
    percent.text = [NSString stringWithFormat:@"%.0f%%", self.progress * 100];
    bar.progress = (float)self.progress;
}

#pragma mark - 交互

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (self.isBusy) return;
        if (indexPath.row == 0) [self pickDocument];
        else [self pickVideo];
        return;
    }

    if (indexPath.section == 1 && indexPath.row == 0) {
        if (self.isBusy) return;
        [self chooseFormat];
        return;
    }

    if (indexPath.section == self.outputSection) {
        AFFilesViewController *files = [[AFFilesViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        [self.navigationController pushViewController:files animated:YES];
    }
}

- (void)chooseFormat
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"输出格式"
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    AFOutputFormat options[] = {AFOutputFormatSilk, AFOutputFormatNB, AFOutputFormatWB, AFOutputFormatM4A};
    for (NSInteger index = 0; index < 4; index++) {
        AFOutputFormat format = options[index];
        NSString *title = [NSString stringWithFormat:@"%@ · %@", AFFormatTitle(format), AFFormatSubtitle(format)];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction *item) {
            self.format = format;
            AFSetCurrentFormat(format);
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
        }];
        if (format == self.format) {
            [action setValue:AFAccentColor() forKey:@"titleTextColor"];
        }
        [sheet addAction:action];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2,
                                                                self.view.bounds.size.height / 2,
                                                                1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)pickDocument
{
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeItem] asCopy:YES];
    picker.allowsMultipleSelection = NO;
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)pickVideo
{
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = [PHPickerFilter videosFilter];
    configuration.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
    if (urls.count == 0) return;
    NSURL *url = urls.firstObject;
    // 固定使用用户可见的原始文件名，而不是临时副本名
    [self startConversionWithURL:url displayName:url.lastPathComponent];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;

    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
        AFPresentAlert(self, @"无法读取", @"相册返回的条目不是视频");
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadFileRepresentationForTypeIdentifier:UTTypeMovie.identifier
                                   completionHandler:^(NSURL *url, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (!url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                AFPresentAlert(strongSelf, @"读取失败", error.localizedDescription ?: @"无法获取视频文件");
            });
            return;
        }
        NSString *displayName = provider.suggestedName.length
            ? provider.suggestedName
            : url.lastPathComponent;
        dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf startConversionWithURL:url displayName:displayName];
        });
    }];
}

#pragma mark - 转换

- (void)startConversionWithURL:(NSURL *)sourceURL displayName:(NSString *)displayName
{
    if (self.isBusy) return;

    AFOutputFormat format = self.format;
    NSString *baseName = AFSanitizedBaseName(displayName.length ? displayName : sourceURL.lastPathComponent);
    NSURL *output = AFUniqueOutputURL(baseName, AFFormatExtension(format));

    self.busy = YES;
    self.progress = 0;
    self.errorText = nil;
    self.currentName = baseName;
    self.statusText = [NSString stringWithFormat:@"正在转换 %@", baseName];
    [self.tableView reloadData];

    NSError *copyError = nil;
    NSURL *input = [self temporaryCopyOfURL:sourceURL error:&copyError];
    if (!input) {
        self.busy = NO;
        self.errorText = [NSString stringWithFormat:@"无法读取所选文件：%@",
                          copyError.localizedDescription ?: @"复制到临时目录失败"];
        [self.tableView reloadData];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            [[NSFileManager defaultManager] removeItemAtURL:input error:nil];
            return;
        }

        NSError *error = nil;
        BOOL ok = NO;

        if (format == AFOutputFormatM4A) {
            ok = [strongSelf exportM4AFromURL:input toURL:output error:&error];
        } else {
            ok = [AMREncoder convertMediaAtURL:input
                                          toURL:output
                                         format:[strongSelf amrFormatFor:format]
                                       progress:^(double value) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    strongSelf.progress = value;
                    [strongSelf refreshProgressCell];
                });
            }
                                          error:&error];
        }

        if (!ok) {
            [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
        }
        [[NSFileManager defaultManager] removeItemAtURL:input error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.busy = NO;
            strongSelf.progress = ok ? 1.0 : 0.0;
            if (ok) {
                strongSelf.statusText = [NSString stringWithFormat:@"已生成 %@", output.lastPathComponent];
                strongSelf.errorText = nil;
            } else {
                strongSelf.statusText = @"转换失败";
                strongSelf.errorText = [NSString stringWithFormat:@"%@：%@",
                                        baseName,
                                        error.localizedDescription ?: @"未知错误"];
            }
            [strongSelf.tableView reloadData];
        });
    });
}

- (AMROutputFormat)amrFormatFor:(AFOutputFormat)format
{
    switch (format) {
        case AFOutputFormatNB: return AMROutputFormatNB;
        case AFOutputFormatWB: return AMROutputFormatWB;
        default:               return AMROutputFormatSilk;
    }
}

- (BOOL)exportM4AFromURL:(NSURL *)input toURL:(NSURL *)output error:(NSError **)error
{
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:input options:nil];
    AVAssetExportSession *session =
        [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!session) {
        if (error) {
            *error = [NSError errorWithDomain:AMREncoderErrorDomain
                                         code:20
                                     userInfo:@{NSLocalizedDescriptionKey: @"这个文件无法导出为 M4A"}];
        }
        return NO;
    }

    [[NSFileManager defaultManager] removeItemAtURL:output error:nil];
    session.outputURL = output;
    session.outputFileType = AVFileTypeAppleM4A;

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    [session exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(sema);
    }];

    __weak typeof(self) weakSelf = self;
    while (dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC))) != 0) {
        double value = session.progress * 0.99;
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf.progress = value;
            [strongSelf refreshProgressCell];
        });
    }

    if (session.status != AVAssetExportSessionStatusCompleted) {
        if (error) *error = session.error;
        return NO;
    }
    return YES;
}

#pragma mark - 路径

- (NSURL *)temporaryCopyOfURL:(NSURL *)url error:(NSError **)error
{
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"incoming"]
                                  isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    NSString *suffix = url.pathExtension.length ? url.pathExtension : @"dat";
    NSURL *target = [directory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    target = [target URLByAppendingPathExtension:suffix];
    [[NSFileManager defaultManager] removeItemAtURL:target error:nil];
    BOOL ok = [[NSFileManager defaultManager] copyItemAtURL:url toURL:target error:error];
    return ok ? target : nil;
}

@end
