//
//  iTermWelcomeCardViewController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardViewController.h"
#import "iTermTipCardActionButton.h"

@implementation iTermTipCardViewController {
    IBOutlet NSTextField *_title;
    IBOutlet NSTextField *_body;
    IBOutlet NSBox *_titleBox;
    IBOutlet NSView *_container;
    NSMutableArray *_actionButtons;
}

- (void)dealloc {
    [_actionButtons release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    [dropShadow setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.3]];
    [dropShadow setShadowOffset:NSMakeSize(0, -1.5)];
    [dropShadow setShadowBlurRadius:2];
    [self.view setWantsLayer:YES];
    [self.view setShadow:dropShadow];
}

- (void)setTitleString:(NSString *)titleString {
    _title.stringValue = titleString;
}

- (void)setColor:(NSColor *)color {
    _titleBox.fillColor = color;
}

- (void)setBodyText:(NSString *)body {
    _body.stringValue = body;
}

- (void)addActionWithTitle:(NSString *)title
                      icon:(NSImage *)image
                     block:(void (^)())block {
    if (!_actionButtons) {
        _actionButtons = [[NSMutableArray alloc] init];
    }
    iTermTipCardActionButton *button = [[[iTermTipCardActionButton alloc] initWithFrame:NSMakeRect(0, 0, _container.bounds.size.width, 0)] autorelease];
    button.title = title;
    [button setIcon:image];
    button.block = block;
    button.target = self;
    button.action = @selector(buttonPressed:);
    [_actionButtons addObject:button];
    [_container addSubview:button];
}

- (void)layoutWithWidth:(CGFloat)width {
    NSRect cardFrame = self.view.frame;
    cardFrame.size.width = width;
    self.view.frame = cardFrame;
    CGFloat diff = self.view.frame.size.height - _body.frame.size.height;
    NSRect bodyFrame = _body.frame;
    bodyFrame.size = [_body sizeThatFits:NSMakeSize(_body.frame.size.width, CGFLOAT_MAX)];

    const CGFloat margin = 4;
    diff += margin;
    bodyFrame.origin.y += margin;
    CGFloat y = 0;
    for (NSButton *actionButton in _actionButtons) {
        [actionButton sizeToFit];
        diff += actionButton.frame.size.height;
        y += actionButton.bounds.size.height;
        bodyFrame.origin.y += actionButton.frame.size.height;
    }
    for (NSButton *actionButton in _actionButtons) {
        y -= actionButton.frame.size.height;
        actionButton.frame = NSMakeRect(0.5,
                                        y,
                                        _container.bounds.size.width - 1,
                                        actionButton.frame.size.height);
    }

    NSRect frame = self.view.frame;
    frame.size.height = bodyFrame.size.height + diff;
    self.view.frame = frame;

    _body.frame = bodyFrame;
}

- (void)buttonPressed:(id)sender {
    iTermTipCardActionButton *button = sender;
    if (button.block) {
        button.block();
    }
}

@end
