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
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "SolidColorView.h"

@interface iTermTipCardFakeDividerView : SolidColorView
@end

@implementation iTermTipCardFakeDividerView

- (void)drawRect:(NSRect)dirtyRect {
    NSRect rect = self.bounds;
    [self.color set];
    NSRectFill(NSMakeRect(rect.origin.x,
                          rect.origin.y + 0.5,
                          rect.size.width,
                          0.5));
}

@end

@interface iTermTipCardView : iTermFlippedView
@end

@implementation iTermTipCardView

- (void)awakeFromNib {
    [self flipSubviews];
}

@end

@interface iTermTipCardContainerView : iTermFlippedView
@end

@implementation iTermTipCardContainerView

- (void)awakeFromNib {
    [self flipSubviews];
    self.layer.borderWidth = 1;
    self.layer.borderColor = [[NSColor redColor] iterm_CGColor];
}

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor whiteColor] set];
    NSRectFill(self.bounds);

    [super drawRect:dirtyRect];

    [[NSColor colorWithCalibratedWhite:0.65 alpha:1] set];
    NSFrameRect(self.bounds);
}

- (BOOL)isFlipped {
    return YES;
}

@end

@interface iTermTipCardViewController()

@property(nonatomic, assign) NSRect postAnimationFrame;

@end

@implementation iTermTipCardViewController {
    IBOutlet NSTextField *_title;
    IBOutlet NSTextField *_body;
    IBOutlet NSBox *_titleBox;
    IBOutlet iTermTipCardContainerView *_container;
    iTermTipCardFakeDividerView *_fakeBottomDivider;
    NSMutableArray *_actionButtons;
}

- (void)dealloc {
    [_actionButtons release];
    [_fakeBottomDivider release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    [dropShadow setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.3]];
    [dropShadow setShadowOffset:NSMakeSize(0, 1.5)];
    [dropShadow setShadowBlurRadius:2];
    [self.view setWantsLayer:YES];
    [self.view setShadow:dropShadow];
    _fakeBottomDivider = [[iTermTipCardFakeDividerView alloc] initWithFrame:NSZeroRect];
    _fakeBottomDivider.hidden = YES;
    _fakeBottomDivider.color = [NSColor colorWithCalibratedWhite:0.85 alpha:1];
    // TODO: root out and remove CGColor
    [_container addSubview:_fakeBottomDivider];
    _titleBox.fillColor = [NSColor colorWithCalibratedRed:120/255.0
                                                    green:178/255.0
                                                     blue:1.0
                                                    alpha:1];
    _container.autoresizesSubviews = NO;
}

- (void)setTitleString:(NSString *)titleString {
    _title.stringValue = titleString;
}

- (void)setColor:(NSColor *)color {
    _titleBox.fillColor = color;
}

- (void)setBodyText:(NSString *)body {
    NSMutableAttributedString *attributedString =
        [[[NSMutableAttributedString alloc] init] autorelease];

    NSDictionary *bigTextAttributes =
        @{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue Light" size:16],
           NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.2 alpha:1] };

    [attributedString iterm_appendString:@"iTerm2 tip of the day: "
                          withAttributes:bigTextAttributes];
    [attributedString iterm_appendString:body
                          withAttributes:bigTextAttributes];

    _body.attributedStringValue = attributedString;
}

- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block {
    if (!_actionButtons) {
        _actionButtons = [[NSMutableArray alloc] init];
    }
    static const CGFloat sideMargin = 1;
    iTermTipCardActionButton *button = [[[iTermTipCardActionButton alloc] initWithFrame:NSMakeRect(sideMargin, 0, _container.bounds.size.width - sideMargin * 2, 0)] autorelease];
    button.autoresizingMask = 0;
    button.title = title;
    [button setIcon:image];
    button.block = block;
    button.target = self;
    button.action = @selector(buttonPressed:);
    NSView *goesBelow = [_actionButtons lastObject] ?: _body;
    [_actionButtons addObject:button];
    // Place later buttons under earlier buttons and all under body so they can animate in and out.
    [_container addSubview:button positioned:NSWindowBelow relativeTo:goesBelow];
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
    static const CGFloat kContainerSideInset = 4;
    static const CGFloat kContainerTopBorder = 1;
    static const CGFloat kContainerBottomBorder = 1;
    NSRect cardFrame = self.view.frame;
    cardFrame.size.width = width;
    CGFloat containerWidth = width - kContainerSideInset * 2;

    static const CGFloat kBodySideMargin = 10;
    NSRect bodyFrame = _body.frame;
    bodyFrame.size = [_body sizeThatFits:NSMakeSize(containerWidth - kBodySideMargin * 2, CGFLOAT_MAX)];
    bodyFrame.origin.x = kBodySideMargin;

    CGFloat totalButtonHeight = 0;
    CGFloat stagedButtonHeight = 0;
    const CGFloat bottomMargin = 8;
    const CGFloat topMargin = 2;
    const CGFloat marginBetweenTextAndButtons = 10;

    // Calculate the height of the buttons
    for (iTermTipCardActionButton *actionButton in _actionButtons) {
        switch (actionButton.animationState) {
            case kTipCardButtonAnimatingIn:
                [actionButton setCollapsed:NO];
                [actionButton sizeToFit];
                stagedButtonHeight += actionButton.frame.size.height;
                break;

            case kTipCardButtonAnimatingOut:
            case kTipCardButtonNotAnimating:
                [actionButton sizeToFit];
                totalButtonHeight += actionButton.frame.size.height;
                break;

            case kTipCardButtonAnimatingOutCurrently:
                [actionButton sizeToFit];
                // Treat as 0 height
                break;
        }
    }

    const CGFloat kMarginBetweenTitleAndBody = 8;

    // Set the y origin of the body text
    bodyFrame.origin.y = NSMaxY(_titleBox.frame) + kMarginBetweenTitleAndBody;

    // Set outermost view's frame
    NSRect frame = cardFrame;
    frame.size.height = (topMargin +
                         kContainerTopBorder +
                         _titleBox.frame.size.height +
                         kMarginBetweenTitleAndBody +
                         bodyFrame.size.height +
                         marginBetweenTextAndButtons +
                         totalButtonHeight +
                         kContainerBottomBorder +
                         bottomMargin);
    frame.origin = newOrigin;
    frame = NSIntegralRect(frame);

    if (!dry) {
        if (animated) {
            self.view.animator.frame = frame;
        } else {
            self.view.frame = frame;
        }
    }

    CGFloat containerHeight = (1 +
                               _titleBox.frame.size.height +
                               kMarginBetweenTitleAndBody +
                               bodyFrame.size.height +
                               marginBetweenTextAndButtons +
                               totalButtonHeight +
                               1);
    NSRect containerFrame = NSMakeRect(kContainerSideInset,
                                       topMargin,
                                       containerWidth,
                                       containerHeight);
    if (!dry) {
        if (animated) {
            _container.animator.frame = containerFrame;
        } else {
            _container.frame = containerFrame;
        }
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
    CGFloat liveY = NSMaxY(bodyFrame) + marginBetweenTextAndButtons;
    CGFloat stageY = NSMaxY(bodyFrame) + totalButtonHeight + marginBetweenTextAndButtons - stagedButtonHeight;
    CGFloat finalYBottom = liveY;
    CGFloat finalYTop = liveY;
    BOOL foundAnimatingOut = NO;
    BOOL foundAnimatingIn = NO;
    for (iTermTipCardActionButton *actionButton in _actionButtons) {
        CGFloat y;
        if (actionButton.animationState == kTipCardButtonAnimatingOutCurrently) {
            continue;
        } else if (actionButton.animationState == kTipCardButtonAnimatingIn) {
            y = stageY;
            stageY += actionButton.frame.size.height;
            finalYTop += actionButton.frame.size.height;
            foundAnimatingIn = YES;
        } else {
            if (actionButton.animationState == kTipCardButtonAnimatingOut) {
                if (!foundAnimatingOut) {
                    foundAnimatingOut = YES;
                    finalYBottom = liveY;
                    finalYTop = liveY;
                }
                finalYTop -= actionButton.frame.size.height;
            }
            y = liveY;
            liveY += actionButton.frame.size.height;
        }
        NSRect buttonFrame = actionButton.frame;
        buttonFrame.origin.y = y;
        buttonFrame.size.width = containerFrame.size.width - 2;
        if (!dry) {
            if (animated) {
                actionButton.animator.frame = buttonFrame;
            } else {
                actionButton.frame = buttonFrame;
            }
        }
    }

    if (foundAnimatingOut || foundAnimatingIn) {
        CGFloat outY = finalYTop;
        CGFloat inY = liveY;
        _postAnimationFrame = frame;
        if (foundAnimatingOut) {
            _fakeBottomDivider.frame = NSMakeRect(1, finalYBottom, _container.frame.size.width - 2, 1);
        } else if (foundAnimatingIn) {
            _fakeBottomDivider.frame = NSMakeRect(1, liveY, _container.frame.size.width - 2, 1);
        }
        for (iTermTipCardActionButton *actionButton in _actionButtons) {
            if (actionButton.animationState == kTipCardButtonAnimatingOut) {
                NSRect rect = actionButton.frame;
                rect.origin.y = outY;
                outY += rect.size.height;
                actionButton.postAnimationFrame = rect;
                _postAnimationFrame.size.height -= rect.size.height;
            } else if (actionButton.animationState == kTipCardButtonAnimatingIn) {
                NSRect rect = actionButton.frame;
                rect.origin.y = inY;
                inY += rect.size.height;
                actionButton.postAnimationFrame = rect;
                _postAnimationFrame.size.height += rect.size.height;
            }
        }
    } else {
        _postAnimationFrame = frame;
    }
    return frame;
}

- (void)buttonPressed:(id)sender {
    iTermTipCardActionButton *button = sender;
    if (button.block) {
        button.block(self);
    }
}

- (NSView *)containerView {
    return _container;
}

- (void)setShowFakeBottomDivider:(BOOL)showFakeBottomDivider {
    _fakeBottomDivider.hidden = !showFakeBottomDivider;
}

- (void)hideCollapsedButtons {
    for (iTermTipCardActionButton *button in _actionButtons) {
        if (button.isCollapsed) {
            button.hidden = YES;
        }
    }
}

@end
