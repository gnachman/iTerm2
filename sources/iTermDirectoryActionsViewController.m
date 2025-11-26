//
//  iTermDirectoryActionsViewController.m
//  iTerm2SharedARC
//

#import "iTermDirectoryActionsViewController.h"
#import "NSAppearance+iTerm.h"
#import "NSStringITerm.h"

@interface iTermDirectoryActionsViewController ()
@property (nonatomic, strong) NSStackView *stackView;
@end

@implementation iTermDirectoryActionsViewController

- (instancetype)initWithDirectoryPath:(NSString *)path {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _directoryPath = [path copy];
    }
    return self;
}

- (void)loadView {
    NSView *containerView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 250, 100)];
    self.view = containerView;
    
    _stackView = [[NSStackView alloc] initWithFrame:containerView.bounds];
    _stackView.orientation = NSUserInterfaceLayoutOrientationVertical;
    _stackView.alignment = NSLayoutAttributeLeading;
    _stackView.spacing = 0;
    _stackView.edgeInsets = NSEdgeInsetsMake(8, 8, 8, 8);
    _stackView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    [containerView addSubview:_stackView];
    
    [self addActionButton:@"Copy Full Path" action:@selector(copyPath:)];
    [self addActionButton:@"Copy Directory Name" action:@selector(copyBasename:)];
    [self addActionButton:@"Reveal in Finder" action:@selector(openInFinder:)];
    [self addSeparator];
    [self addActionButton:@"Open in New Window" action:@selector(openInNewWindow:)];
    [self addActionButton:@"Open in New Tab" action:@selector(openInNewTab:)];
}

- (void)addActionButton:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title
                                          target:self
                                          action:action];
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.bordered = NO;
    button.alignment = NSTextAlignmentLeft;
    button.contentTintColor = nil;
    
    if (self.font) {
        button.font = self.font;
    }
    
    [button setButtonType:NSButtonTypeMomentaryChange];
    
    [_stackView addArrangedSubview:button];
}

- (void)addSeparator {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 200, 1)];
    separator.boxType = NSBoxSeparator;
    [_stackView addArrangedSubview:separator];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self updateLayout];
    [self updateColors];
}

- (void)viewWillAppear {
    [super viewWillAppear];
    [self updateColors];
}

- (void)updateColors {
    NSColor *textColor;
    if (self.view.effectiveAppearance.it_isDark) {
        textColor = [NSColor whiteColor];
    } else {
        textColor = [NSColor blackColor];
    }
    
    for (NSView *subview in _stackView.arrangedSubviews) {
        if ([subview isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)subview;
            NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithAttributedString:button.attributedTitle];
            [attributedTitle addAttribute:NSForegroundColorAttributeName
                                    value:textColor
                                    range:NSMakeRange(0, attributedTitle.length)];
            button.attributedTitle = attributedTitle;
        }
    }
}

- (void)updateLayout {
    CGFloat maxWidth = 0;
    for (NSView *subview in _stackView.arrangedSubviews) {
        [subview sizeToFit];
        maxWidth = MAX(maxWidth, subview.frame.size.width);
    }
    
    CGFloat height = 0;
    for (NSView *subview in _stackView.arrangedSubviews) {
        height += subview.frame.size.height;
    }
    height += _stackView.spacing * (_stackView.arrangedSubviews.count - 1);
    height += _stackView.edgeInsets.top + _stackView.edgeInsets.bottom;
    
    self.view.frame = NSMakeRect(0, 0, 
                                 maxWidth + _stackView.edgeInsets.left + _stackView.edgeInsets.right,
                                 height);
}

- (void)copyPath:(id)sender {
    [self.delegate directoryActionsDidSelectCopyPath];
}

- (void)copyBasename:(id)sender {
    [self.delegate directoryActionsDidSelectCopyBasename];
}

- (void)openInFinder:(id)sender {
    [self.delegate directoryActionsDidSelectOpenInFinder];
}

- (void)openInNewWindow:(id)sender {
    [self.delegate directoryActionsDidSelectOpenInNewWindow];
}

- (void)openInNewTab:(id)sender {
    [self.delegate directoryActionsDidSelectOpenInNewTab];
}

@end
