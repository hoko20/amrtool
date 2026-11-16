//
//  AFTextViewController.m
//  AudioForge
//

#import "AFUI.h"

@interface AFTextViewController ()
@property (nonatomic, copy) NSString *text;
@end

@implementation AFTextViewController

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.title = title;
        _text = [text copy];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UITextView *textView = [UITextView new];
    textView.text = self.text;
    textView.editable = NO;
    textView.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    textView.textColor = UIColor.labelColor;
    textView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    textView.textContainerInset = UIEdgeInsetsMake(20, 16, 32, 16);
    textView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:textView];
    [NSLayoutConstraint activateConstraints:@[
        [textView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
}

@end
