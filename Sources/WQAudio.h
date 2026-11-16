//
//  WQAudio.h
//  SandboxExplorer
//
//  音频转换功能的共享定义：格式、输出目录、文件命名与两个页面。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQAudioFormat) {
    WQAudioFormatSilk = 0,  // SILK v3，微信 / QQ 语音条 .aud
    WQAudioFormatAMRNB,     // AMR-NB 12.2 kbps
    WQAudioFormatAMRWB,     // AMR-WB 23.85 kbps
    WQAudioFormatM4A,       // AAC 96 kbps
};

NSString *WQAudioFormatTitle(WQAudioFormat format);
NSString *WQAudioFormatDetail(WQAudioFormat format);
NSString *WQAudioFormatExtension(WQAudioFormat format);

WQAudioFormat WQAudioCurrentFormat(void);
void WQAudioSetCurrentFormat(WQAudioFormat format);

/// Documents/AudioForge，转换输出统一放在这里。
NSString *WQAudioOutputDirectory(void);
/// 输出目录下的 .aud / .amr / .m4a，按修改时间倒序。
NSArray<NSString *> *WQAudioOutputFiles(void);
NSURL *WQAudioUniqueOutputURL(NSString *baseName, NSString *extension);
/// 去掉扩展名与路径分隔符，空名称回退为「音频」。
NSString *WQAudioBaseName(NSString *name);

/// 表格顶部的多行说明，宽度变化时由调用方重新调用。
void WQAudioSetTableHeader(UITableView *tableView, NSString *text);

@interface WQAudioConvertViewController : UITableViewController
@end

@interface WQAudioFilesViewController : UITableViewController
@end

NS_ASSUME_NONNULL_END
