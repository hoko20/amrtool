//
//  WQAudioConvertViewController.m
//  SandboxExplorer
//

#import "WQAudio.h"
#import "WQKit.h"
#import "WQUI.h"
#import "WQAudioEncoder.h"
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

typedef NS_ENUM(NSInteger, WQConvertSection) {
    WQConvertSectionImport = 0,
    WQConvertSectionFormat = 1,
    WQConvertSectionProgress = 2,
    WQConvertSectionOutput = 3,
};

@interface WQAudioConvertViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic) BOOL busy;
@property (nonatomic) double progress;
@property (nonatomic) CGFloat lastHeaderWidth;
@property (nonatomic, strong) UITableViewCell *progressCell;
@property (nonatomic, strong) UIProgressView *progressView;
@end

@implementation WQAudioConvertViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.navigationItem.title = @"转换";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 56;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(refresh:)];
    [self refreshHeader];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self refreshHeader];
    [self.tableView reloadData];
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
    [self.tableView reloadData];
}

- (NSString *)headerText
{
    WQAudioFormat format = WQAudioCurrentFormat();
    return [NSString stringWithFormat:
            @"把 MP3 / MP4 / M4A / MOV / WAV 转换为语音文件，也可从相册选择视频。\n"
            @"当前格式：%@（%@）\n"
            @"所有转换都在本机完成，不会上传任何音频。",
            WQAudioFormatTitle(format), WQAudioFormatDetail(format)];
}

- (void)refreshHeader
{
    self.lastHeaderWidth = self.tableView.bounds.size.width;
    WQAudioSetTableHeader(self.tableView, [self headerText]);
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
        case WQConvertSectionImport:   return 2;
        case WQConvertSectionFormat:   return 4;
        case WQConvertSectionProgress: return self.busy ? 1 : 0;
        default:                       return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case WQConvertSectionImport:   return @"导入";
        case WQConvertSectionFormat:   return @"输出格式";
        case WQConvertSectionProgress: return self.busy ? @"转换进度" : nil;
        default:                       return @"输出";
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if (section == WQConvertSectionImport) return @"支持音频文件与视频文件（只提取声音）。";
    if (section == WQConvertSectionFormat) return @"SILK .aud 可直接作为微信 / QQ 语音发送；AMR 适合旧设备；M4A 兼容性最广。";
    if (section == WQConvertSectionOutput) return @"文件保存在 Documents/AudioForge，也可在「文件」tab 中查看。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == WQConvertSectionProgress) return [self configuredProgressCell];

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                            reuseIdentifier:@"Cell"];
    cell.detailTextLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    if (indexPath.section == WQConvertSectionImport) {
        cell.textLabel.text = indexPath.row == 0 ? @"选择文件" : @"从相册选择视频";
        cell.detailTextLabel.text = indexPath.row == 0 ? @"MP3 / MP4 / M4A / MOV / WAV" : @"只提取视频中的音轨";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == WQConvertSectionFormat) {
        WQAudioFormat format = (WQAudioFormat)indexPath.row;
        cell.textLabel.text = WQAudioFormatTitle(format);
        cell.detailTextLabel.text = WQAudioFormatDetail(format);
        cell.accessoryType = WQAudioCurrentFormat() == format
            ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    } else {
        NSArray<NSString *> *files = WQAudioOutputFiles();
        uint64_t total = 0;
        for (NSString *name in files) {
            total += [NSFileManager.defaultManager
                      attributesOfItemAtPath:[WQAudioOutputDirectory() stringByAppendingPathComponent:name]
                                       error:nil][NSFileSize].unsignedLongLongValue;
        }
        cell.textLabel.text = @"转换输出";
        cell.detailTextLabel.text = files.count
            ? [NSString stringWithFormat:@"%lu 个文件 · %@", (unsigned long)files.count, WQFormatBytes(total)]
            : @"还没有转换文件";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (UITableViewCell *)configuredProgressCell
{
    if (!self.progressCell) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                        reuseIdentifier:nil];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIProgressView *progress = [[UIProgressView alloc] initWithFrame:CGRectMake(0, 0, 120, 4)];
        cell.accessoryView = progress;
        self.progressCell = cell;
        self.progressView = progress;
    }
    self.progressCell.textLabel.text = [self progressText];
    self.progressView.progress = (float)MIN(1.0, MAX(0.0, self.progress));
    return self.progressCell;
}

- (NSString *)progressText
{
    return [NSString stringWithFormat:@"正在转换 %d%%", (int)lround(MIN(1.0, MAX(0.0, self.progress)) * 100)];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (self.busy) {
        WQPresentAlert(self, @"正在转换", @"请等待当前任务完成。");
        return;
    }

    if (indexPath.section == WQConvertSectionImport) {
        indexPath.row == 0 ? [self pickFile] : [self pickVideo];
    } else if (indexPath.section == WQConvertSectionFormat) {
        WQAudioFormat format = (WQAudioFormat)indexPath.row;
        WQAudioSetCurrentFormat(format);
        [self refreshHeader];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:WQConvertSectionFormat]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    } else if (indexPath.section == WQConvertSectionOutput) {
        [self.navigationController pushViewController:[WQAudioFilesViewController new] animated:YES];
    }
}

#pragma mark - Picking

- (void)pickFile
{
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeAudio, UTTypeMovie, UTTypeAudiovisualContent]
                            asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
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
    NSURL *url = urls.firstObject;
    if (url) [self importURL:url displayName:url.lastPathComponent];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results
{
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;

    NSItemProvider *provider = result.itemProvider;
    NSString *suggested = provider.suggestedName ?: @"视频";
    [provider loadFileRepresentationForTypeIdentifier:UTTypeMovie.identifier
                                   completionHandler:^(NSURL *url, NSError *error) {
        if (!url) {
            NSString *message = error.localizedDescription ?: @"请换一个视频试试";
            dispatch_async(dispatch_get_main_queue(), ^{
                WQPresentAlert(self, @"无法读取视频", message);
            });
            return;
        }

        NSString *extension = url.pathExtension.length ? url.pathExtension : @"mov";
        NSURL *temp = [NSURL fileURLWithPath:
            [NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat:@"wqaudio-%@.%@", NSUUID.UUID.UUIDString, extension]]];
        NSError *copyError = nil;
        BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url toURL:temp error:&copyError];
        if (!copied) {
            NSString *message = copyError.localizedDescription ?: @"请重试";
            dispatch_async(dispatch_get_main_queue(), ^{
                WQPresentAlert(self, @"无法读取视频", message);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self startConversionWithURL:temp displayName:suggested];
        });
    }];
}

- (void)importURL:(NSURL *)url displayName:(NSString *)displayName
{
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *extension = url.pathExtension.length ? url.pathExtension : @"dat";
    NSURL *temp = [NSURL fileURLWithPath:
        [NSTemporaryDirectory() stringByAppendingPathComponent:
         [NSString stringWithFormat:@"wqaudio-%@.%@", NSUUID.UUID.UUIDString, extension]]];
    NSError *error = nil;
    BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url toURL:temp error:&error];
    if (scoped) [url stopAccessingSecurityScopedResource];

    if (!copied) {
        WQPresentAlert(self, @"无法读取文件", error.localizedDescription ?: @"请重试");
        return;
    }
    [self startConversionWithURL:temp displayName:displayName];
}

#pragma mark - Conversion

- (WQAudioEncodeFormat)encoderFormat:(WQAudioFormat)format
{
    switch (format) {
        case WQAudioFormatAMRNB: return WQAudioEncodeFormatAMRNB;
        case WQAudioFormatAMRWB: return WQAudioEncodeFormatAMRWB;
        default:                 return WQAudioEncodeFormatSilk;
    }
}

- (void)startConversionWithURL:(NSURL *)url displayName:(NSString *)displayName
{
    WQAudioFormat format = WQAudioCurrentFormat();
    NSURL *output = WQAudioUniqueOutputURL(displayName, WQAudioFormatExtension(format));

    self.busy = YES;
    self.progress = 0;
    [self.tableView reloadData];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL success = NO;
        WQAudioProgressBlock progress = ^(double value) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!self.busy) return;
                self.progress = value;
                [self configuredProgressCell];
            });
        };

        if (format == WQAudioFormatM4A) {
            success = [WQAudioEncoder exportM4AURL:url toURL:output progress:progress error:&error];
        } else {
            success = [WQAudioEncoder convertURL:url
                                           toURL:output
                                          format:[self encoderFormat:format]
                                        progress:progress
                                           error:&error];
        }

        [NSFileManager.defaultManager removeItemAtURL:url error:nil];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy = NO;
            self.progress = 0;
            [self.tableView reloadData];
            if (success) {
                WQLog(@"音频转换完成：%@", output.lastPathComponent);
                WQPresentAlert(self, @"转换完成",
                    [NSString stringWithFormat:@"%@\n已保存到「转换输出」。", output.lastPathComponent]);
            } else {
                WQPresentAlert(self, @"转换失败", error.localizedDescription ?: @"未知错误");
            }
        });
    });
}

@end
