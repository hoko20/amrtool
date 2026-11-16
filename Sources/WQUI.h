//
//  WQUI.h
//  AudioForge
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WQOutputFormat) {
    WQOutputFormatSilk = 0,
    WQOutputFormatNB = 1,
    WQOutputFormatWB = 2,
    WQOutputFormatM4A = 3,
};

@interface WQAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface WQSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

/// 首页：导入、选择格式、转换、进入输出列表
@interface WQConvertViewController : UITableViewController
@end

/// 输出文件列表（Documents 下的 amr / aud / m4a）
@interface WQFilesViewController : UITableViewController
@end

/// 工具：清空输出、存储路径、编码说明
@interface WQToolsViewController : UITableViewController
@end

/// 我的：版本与开源声明
@interface WQProfileViewController : UITableViewController
@end

/// 只读文本页
@interface WQTextViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text;
@end

UIColor *WQAccentColor(void);
NSString *WQDocumentsPath(void);
NSString *WQFormatTitle(WQOutputFormat format);
NSString *WQFormatSubtitle(WQOutputFormat format);
NSString *WQFormatExtension(WQOutputFormat format);
NSString *WQFormatSummary(WQOutputFormat format);
WQOutputFormat WQCurrentFormat(void);
void WQSetCurrentFormat(WQOutputFormat format);

void WQPresentAlert(UIViewController *from, NSString *title, NSString *message);

NS_ASSUME_NONNULL_END
