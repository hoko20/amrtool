//
//  EditorViewController.m
//  SandboxExplorer
//
//  Plain-text viewer / editor. Writes go through WQWrite (in-place, same inode)
//  or WQCreateFile for new files.
//

#import "WQUI.h"
#import "WQKit.h"

@interface WQTextViewController ()
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic) BOOL editable;
@property (nonatomic, copy) WQEditorSaveBlock save;
@property (nonatomic, strong) UITextView *textView;
@end

@implementation WQTextViewController

- (instancetype)initWithTitle:(NSString *)title
                         text:(NSString *)text
                     editable:(BOOL)editable
                         save:(WQEditorSaveBlock _Nullable)save
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _initialText = text ?: @"";
        _editable = editable;
        _save = [save copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UITextView *textView = [UITextView new];
    textView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    textView.text = self.initialText;
    textView.editable = self.editable;
    textView.selectable = YES;
    textView.alwaysBounceVertical = YES;
    textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    textView.autocorrectionType = UITextAutocorrectionTypeNo;
    textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    textView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    self.textView = textView;
    [self.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
    ]];

    if (self.editable) {
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                          target:self action:@selector(cancel:)];
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                          target:self action:@selector(save:)];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(keyboardChanged:)
                                                   name:UIKeyboardWillChangeFrameNotification
                                                 object:nil];
    } else {
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"复制全部" style:UIBarButtonItemStylePlain
                                           target:self action:@selector(copyAll:)];
    }
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)keyboardChanged:(NSNotification *)note
{
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:end fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(local));
    UIEdgeInsets inset = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.textView.contentInset = inset;
    self.textView.scrollIndicatorInsets = inset;
}

- (void)cancel:(id)sender
{
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)save:(id)sender
{
    [self.textView resignFirstResponder];
    NSString *text = self.textView.text ?: @"";
    __weak typeof(self) weakSelf = self;
    if (self.save) {
        self.save(text, ^(BOOL ok, NSString *message) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                if (!strongSelf) return;
                WQPresentAlert(strongSelf, ok ? @"完成" : @"失败", message);
                if (ok) [strongSelf.navigationController popViewControllerAnimated:YES];
            });
        });
    }
}

- (void)copyAll:(id)sender
{
    WQCopyToPasteboard(self.textView.text);
    WQPresentAlert(self, @"已复制", @"全部文本已复制到剪贴板");
}

@end
