//
//  WQUI.h
//  SandboxExplorer
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface WQAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface WQSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@interface WQHomeViewController : UITableViewController
@end

@interface WQContainersViewController : UITableViewController
@end

@interface WQBrowserViewController : UITableViewController
- (instancetype)initWithPath:(NSString *)path title:(NSString *_Nullable)title;
@end

typedef void (^WQEditorSaveBlock)(NSString *text, void (^completion)(BOOL ok, NSString *message));

@interface WQTextViewController : UIViewController
/// editable=YES shows a Save button and calls `save`; editable=NO is a viewer.
- (instancetype)initWithTitle:(NSString *)title
                         text:(NSString *)text
                     editable:(BOOL)editable
                         save:(WQEditorSaveBlock _Nullable)save;
@end

@interface WQToolsViewController : UITableViewController
@end

/// Shared helpers used by all screens.
void WQPresentAlert(UIViewController *from, NSString *title, NSString *message);
void WQCopyToPasteboard(NSString *text);
UIAlertController *WQInputAlert(NSString *title, NSString *message, NSString *placeholder,
                                NSString *_Nullable initial, void (^commit)(NSString *value));
UIColor *WQAccentColor(void);

NS_ASSUME_NONNULL_END
