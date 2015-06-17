//
//  iTermWelcomeCardViewController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardViewController.h"
#import "iTermFlippedView.h"
#import "iTermTipCardActionButton.h"

@interface iTermTipCardContainerView : iTermFlippedView
@end

@implementation iTermTipCardContainerView

- (void)awakeFromNib {
    [self flipSubviews];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] set];
    NSRectFill(self.bounds);

    NSRect bounds = self.bounds;
    [[NSColor colorWithCalibratedWhite:0.65 alpha:1] set];
    NSFrameRect(self.bounds);

    [super drawRect:dirtyRect];
}

- (BOOL)isFlipped {
    return YES;
}

@end

@implementation iTermTipCardViewController {
    IBOutlet NSTextField *_title;
    IBOutlet NSTextField *_body;
    IBOutlet NSBox *_titleBox;
    IBOutlet iTermTipCardContainerView *_container;
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
    _container.autoresizesSubviews = NO;
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

- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block {
    if (!_actionButtons) {
        _actionButtons = [[NSMutableArray alloc] init];
    }
    iTermTipCardActionButton *button = [[[iTermTipCardActionButton alloc] initWithFrame:NSMakeRect(1, 0, _container.bounds.size.width - 2, 0)] autorelease];
    button.autoresizingMask = 0;
    button.title = title;
    [button setIcon:image];
    button.block = block;
    button.target = self;
    button.action = @selector(buttonPressed:);
    [_actionButtons addObject:button];
    [_container addSubview:button];
    return button;
}

- (iTermTipCardActionButton *)actionWithTitle:(NSString *)title {
    for (iTermTipCardActionButton *button in _actionButtons) {
        if ([button.title isEqual:title]) {
            return button;
        }
    }
    return nil;
}

- (void)removeActionWithTitle:(NSString *)title {
    iTermTipCardActionButton *button = [self actionWithTitle:title];
    if (button) {
        [_actionButtons removeObject:button];
        [button removeFromSuperview];
    }
}

- (NSSize)sizeThatFits:(NSSize)size {
    NSRect desiredRect = [self performLayoutForWidth:size.width
                                            animated:NO
                                                 dry:YES
                                              origin:self.view.frame.origin];
    return desiredRect.size;
}

- (void)layoutWithWidth:(CGFloat)width animated:(BOOL)animated origin:(NSPoint)newOrigin {
    [self performLayoutForWidth:width animated:animated dry:NO origin:newOrigin];
}

- (NSRect)performLayoutForWidth:(CGFloat)width
                       animated:(BOOL)animated
                            dry:(BOOL)dry
                         origin:(NSPoint)newOrigin {
    NSRect cardFrame = self.view.frame;
    cardFrame.size.width = width;
    NSRect bodyFrame = _body.frame;
    bodyFrame.size = [_body sizeThatFits:NSMakeSize(_body.frame.size.width, CGFLOAT_MAX)];

    CGFloat totalButtonHeight = 0;
    const CGFloat bottomMargin = 8;
    const CGFloat topMargin = 2;
    const CGFloat marginBetweenTextAndButtons = 6;

    // Calculate the height of the buttons
    for (NSButton *actionButton in _actionButtons) {
        [actionButton sizeToFit];
        totalButtonHeight += actionButton.frame.size.height;
    }

    const CGFloat kMarginBetweenTitleAndBody = 8;

    // Set the y origin of the body text
    bodyFrame.origin.y = NSMaxY(_titleBox.frame) + kMarginBetweenTitleAndBody;

    // Set outermost view's frame
    NSRect frame = cardFrame;
    frame.size.height = (topMargin +
                         1 +
                         _titleBox.frame.size.height +
                         kMarginBetweenTitleAndBody +
                         bodyFrame.size.height +
                         marginBetweenTextAndButtons +
                         totalButtonHeight +
                         1 +
                         bottomMargin);
    frame.origin = newOrigin;
    if (dry) {
        return frame;
    }

    // Don't need to worry about dry from here on down.
    if (animated) {
        self.view.animator.frame = frame;
    } else {
        self.view.frame = frame;
    }

    NSRect containerFrame = self.view.bounds;
    containerFrame.origin.x = 4;
    containerFrame.origin.y = bottomMargin;
    containerFrame.size.width -= 8;
    containerFrame.size.height = (1 +
                                  _titleBox.frame.size.height +
                                  kMarginBetweenTitleAndBody +
                                  bodyFrame.size.height +
                                  marginBetweenTextAndButtons +
                                  totalButtonHeight +
                                  1);
    if (animated) {
        _container.animator.frame = containerFrame;
    } else {
        _container.frame = containerFrame;
    }

    NSRect titleFrame = _titleBox.frame;
    titleFrame.size.width = containerFrame.size.width - 2;
    if (animated) {
        _titleBox.animator.frame = titleFrame;
    } else {
        _titleBox.frame = titleFrame;
    }

    if (animated) {
        _body.animator.frame = bodyFrame;
    } else {
        _body.frame = bodyFrame;
    }

    // Lay buttons out from top to bottom
    CGFloat y = NSMaxY(bodyFrame) + marginBetweenTextAndButtons;
    for (NSButton *actionButton in _actionButtons) {
        NSRect buttonFrame = NSMakeRect(1,
                                        y,
                                        _container.bounds.size.width - 2,
                                        actionButton.frame.size.height);
        if (animated) {
            actionButton.animator.frame = buttonFrame;
        } else {
            actionButton.frame = buttonFrame;
        }
        y += actionButton.frame.size.height;
    }

    return frame;
}

- (void)buttonPressed:(id)sender {
    iTermTipCardActionButton *button = sender;
    if (button.block) {
        button.block(self);
    }
}

@end
