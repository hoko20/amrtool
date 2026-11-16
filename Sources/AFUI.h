//
//  AFUI.h
//  AudioForge
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, AFOutputFormat) {
    AFOutputFormatSilk = 0,
    AFOutputFormatNB = 1,
    AFOutputFormatWB = 2,
    AFOutputFormatM4A = 3,
};

@interface AFAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface AFSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

/// 首页：导入、选择格式、转换、进入输出列表
@interface AFConvertViewController : UITableViewController
@end

/// 输出文件列表（Documents 下的 amr / aud / m4a）
@interface AFFilesViewController : UITableViewController
@end

/// 工具：清空输出、存储路径、编码说明
@interface AFToolsViewController : UITableViewController
@end

/// 我的：版本与开源声明
@interface AFProfileViewController : UITableViewController
@end

/// 只读文本页
@interface AFTextViewController : UIViewController
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text;
@end

UIColor *AFAccentColor(void);
NSString *AFDocumentsPath(void);
NSString *AFFormatTitle(AFOutputFormat format);
NSString *AFFormatSubtitle(AFOutputFormat format);
NSString *AFFormatExtension(AFOutputFormat format);
NSString *AFFormatSummary(AFOutputFormat format);
AFOutputFormat AFCurrentFormat(void);
void AFSetCurrentFormat(AFOutputFormat format);

void AFPresentAlert(UIViewController *from, NSString *title, NSString *message);

NS_ASSUME_NONNULL_END
