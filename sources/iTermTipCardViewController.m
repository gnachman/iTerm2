//
//  iTermWelcomeCardViewController.m
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import "iTermTipCardViewController.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermFlippedView.h"
#import "iTermTipCardActionButton.h"
#import "NSColor+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "SolidColorView.h"

#import <QuartzCore/QuartzCore.h>

static const CGFloat kButtonSideInset = 0;
static const CGFloat kContainerSideInset = 0;
static const CGFloat kContainerTopBorder = 1;
static const CGFloat kContainerBottomBorder = 1;
static const CGFloat kBodySideMargin = 10;
static const CGFloat kBodyBottomMargin = 6;
static const CGFloat kCardBottomMargin = 8;
static const CGFloat kCardTopMargin = 2;
static const CGFloat kMarginBetweenTextAndButtons = 0;
static const CGFloat kMarginBetweenTitleAndBody = 8;

// A temporary divider used at the bottom of the card while it's growing in height.
@interface iTermTipCardFakeDividerView : SolidColorView
@end

@implementation iTermTipCardFakeDividerView

- (void)drawRect:(NSRect)dirtyRect {
    dirtyRect = NSIntersectionRect(dirtyRect, self.bounds);
    NSRect rect = self.bounds;
    [self.color set];
    NSRectFill(NSMakeRect(rect.origin.x,
                          rect.origin.y + 0.5,
                          rect.size.width,
                          0.5));
}

@end

// Root view in the xib. I need a flipped view and this makes the xib match up
// with reality by flipping its subviews on awakeFromNib.
@interface iTermTipCardView : iTermFlippedView
@end

@implementation iTermTipCardView

- (void)awakeFromNib {
    [self flipSubviews];
}

@end

// Bordered container view. Just a flipped view that draws a thin border around
// its perimeter. Used in the xib.
@interface iTermTipCardContainerView : iTermFlippedView
@end

@implementation iTermTipCardContainerView

- (void)awakeFromNib {
    [self flipSubviews];
    [self setWantsLayer:YES];
    self.layer.backgroundColor = [[NSColor whiteColor] CGColor];
    self.layer.borderColor = [[NSColor colorWithCalibratedWhite:0.65 alpha:1] CGColor];
    self.layer.borderWidth = 1;
}

@end

@interface iTermTipCardViewController()<DraggableNSBoxDelegate>
@end

@implementation iTermTipCardViewController {
    IBOutlet NSTextField *_title;
    IBOutlet NSTextField *_body;
    IBOutlet DraggableNSBox *_titleBox;
    IBOutlet iTermTipCardContainerView *_container;

    // A view that sits above the buttons and below the body content to hide staged buttons.
    IBOutlet SolidColorView *_coverView;

    iTermTipCardFakeDividerView *_fakeBottomDivider;
    NSMutableArray *_actionButtons;

    // When performing layout with an animation, the new frame is saved here.
    NSRect _postAnimationFrame;
}

- (void)dealloc {
    [_actionButtons release];
    [_fakeBottomDivider release];
    [super dealloc];
}

- (void)awakeFromNib {
    _titleBox.delegate = self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    _coverView.color = [NSColor whiteColor];

    // Add a shadow to the card.
    NSShadow *dropShadow = [[[NSShadow alloc] init] autorelease];
    [dropShadow setShadowColor:[[NSColor blackColor] colorWithAlphaComponent:0.3]];
    [dropShadow setShadowOffset:NSMakeSize(0, 1.5)];
    [dropShadow setShadowBlurRadius:2];
    [self.view setWantsLayer:YES];
    [self.view setShadow:dropShadow];

    // Create the fake bottom divider to be used later.
    _fakeBottomDivider = [[iTermTipCardFakeDividerView alloc] initWithFrame:NSZeroRect];
    _fakeBottomDivider.hidden = YES;
    _fakeBottomDivider.color = [NSColor colorWithCalibratedWhite:0.85 alpha:1];
    [_container addSubview:_fakeBottomDivider];

    // We do almost all manual layout here.
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

    NSMutableParagraphStyle *bigTextParagraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [bigTextParagraphStyle setParagraphSpacing:4];
    NSDictionary *bigTextAttributes =
    @{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue Light" size:16] ?: [NSFont systemFontOfSize:16],
       NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.2 alpha:1],
       NSParagraphStyleAttributeName: bigTextParagraphStyle };

    NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [paragraphStyle setAlignment:NSTextAlignmentRight];
    NSDictionary *signatureAttributes =
    @{ NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue Light Italic" size:12] ?: [NSFont systemFontOfSize:12],
       NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.3 alpha:1],
       NSParagraphStyleAttributeName: paragraphStyle};

    [attributedString iterm_appendString:body
                          withAttributes:bigTextAttributes];
    [attributedString iterm_appendString:@"\n"
                          withAttributes:bigTextAttributes];
    [attributedString iterm_appendString:@"iTerm2 tip of the day"
                          withAttributes:signatureAttributes];

    _body.attributedStringValue = attributedString;
}

- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block {
    return [self addActionWithTitle:title shortcut:nil icon:image block:block];
}

- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                        shortcut:(NSString *)shortcut
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block {
    if (!_actionButtons) {
        _actionButtons = [[NSMutableArray alloc] init];
    }

    iTermTipCardActionButton *button = [[[iTermTipCardActionButton alloc] initWithFrame:NSMakeRect(kButtonSideInset, 0, _container.bounds.size.width - kButtonSideInset * 2, 0)] autorelease];
    button.autoresizingMask = 0;
    button.title = title;
    button.shortcut = shortcut;
    [button setIcon:image];
    button.block = block;
    button.target = self;
    button.action = @selector(buttonPressed:);
    button.numberOfButtonsInRow = 1;
    NSView *viewToPlaceButtonBelow = [_actionButtons lastObject] ?: _coverView;
    [_actionButtons addObject:button];
    // Place later buttons under earlier buttons and all under body so they can animate in and out.
    [_container addSubview:button positioned:NSWindowBelow relativeTo:viewToPlaceButtonBelow];

    return button;
}

- (void)combineActionWithTitle:(NSString *)leftTitle andTitle:(NSString *)rightTitle {
    iTermTipCardActionButton *left = [self actionWithTitle:leftTitle];
    iTermTipCardActionButton *right = [self actionWithTitle:rightTitle];
    if (!left || !right) {
        return;
    }
    NSRect frame = left.frame;
    frame.size.width = round(frame.size.width / 2);
    left.frame = frame;
    left.indexInRow = 0;
    left.numberOfButtonsInRow = 2;

    frame.origin.x = NSMaxX(frame);
    frame.size.width = _container.frame.size.width - frame.size.width - kContainerSideInset * 2;
    right.frame = frame;
    right.indexInRow = 1;
    right.numberOfButtonsInRow = 2;

    [[left retain] autorelease];
    [_actionButtons removeObject:left];
    [_actionButtons insertObject:left atIndex:[_actionButtons indexOfObject:right]];
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
                                                 dry:YES
                                              origin:self.view.frame.origin];
    return desiredRect.size;
}

- (void)layoutWithWidth:(CGFloat)width origin:(NSPoint)newOrigin {
    [self performLayoutForWidth:width dry:NO origin:newOrigin];
}

// "dry" means frames are calculated but not changed.
// Returns what the frame for self.view would be (or will be, if dry==NO)
- (NSRect)performLayoutForWidth:(CGFloat)width
                            dry:(BOOL)dry
                         origin:(NSPoint)newOrigin {
    CGFloat containerWidth = width - kContainerSideInset * 2;

    // Compute size of body text.
    NSRect bodyFrame = _body.frame;
    bodyFrame.size = [_body sizeThatFits:NSMakeSize(containerWidth - kBodySideMargin * 2, CGFLOAT_MAX)];
    bodyFrame.size.height += kBodyBottomMargin;
    bodyFrame.origin.x = kBodySideMargin;
    bodyFrame.origin.y = NSMaxY(_titleBox.frame) + kMarginBetweenTitleAndBody;

    // Calculate the height of the buttons
    CGFloat totalButtonHeight = 0;  // visible buttons
    CGFloat stagedButtonHeight = 0;  // buttons stacked behind visible buttons

    for (iTermTipCardActionButton *actionButton in _actionButtons) {
        switch (actionButton.animationState) {
            case kTipCardButtonAnimatingIn:
                [actionButton setCollapsed:NO];
                [actionButton sizeToFit];
                if (actionButton.indexInRow == 0) {
                    stagedButtonHeight += actionButton.frame.size.height;
                }
                break;

            case kTipCardButtonAnimatingOut:
            case kTipCardButtonNotAnimating:
                [actionButton sizeToFit];
                if (actionButton.indexInRow == 0) {
                    totalButtonHeight += actionButton.frame.size.height;
                }
                break;

            case kTipCardButtonAnimatingOutCurrently:
                [actionButton sizeToFit];
                // Treat as 0 height
                break;
        }
    }

    // Save the current frame but update its width.
    NSRect cardFrame = self.view.frame;
    cardFrame.size.width = width;

    // Calculate outermost view's frame
    NSRect frame = cardFrame;
    frame.size.height = (kCardTopMargin +
                         kContainerTopBorder +
                         _titleBox.frame.size.height +
                         kMarginBetweenTitleAndBody +
                         bodyFrame.size.height +
                         kMarginBetweenTextAndButtons +
                         totalButtonHeight +
                         kContainerBottomBorder +
                         kCardBottomMargin);
    frame.origin = newOrigin;
    frame = NSIntegralRect(frame);

    // Calculate the container's frame.
    CGFloat containerHeight = (1 +
                               _titleBox.frame.size.height +
                               kMarginBetweenTitleAndBody +
                               bodyFrame.size.height +
                               kMarginBetweenTextAndButtons +
                               totalButtonHeight +
                               1);
    NSRect containerFrame = NSMakeRect(kContainerSideInset,
                                       kCardTopMargin,
                                       containerWidth,
                                       containerHeight);

    // Calculate title's frame
    NSRect titleFrame = _titleBox.frame;
    titleFrame.size.width = containerFrame.size.width - 2;

    // Calculate frame for cover view
    NSRect coverViewFrame = NSMakeRect(1,
                                       NSMaxY(titleFrame),
                                       containerWidth - 2,
                                       NSHeight(containerFrame) - 1 - NSMaxY(titleFrame) - totalButtonHeight);
    // Set frames if not a dry run.
    if (!dry) {
        self.view.frame = frame;
        _container.frame = containerFrame;
        _titleBox.frame = titleFrame;
        _body.frame = bodyFrame;
        _coverView.frame = coverViewFrame;
    }

    // Lay buttons out from top to bottom
    CGFloat liveY = NSMaxY(bodyFrame) + kMarginBetweenTextAndButtons;
    CGFloat stageY = NSMaxY(bodyFrame) + totalButtonHeight + kMarginBetweenTextAndButtons - stagedButtonHeight;
    CGFloat finalYBottom = liveY;
    CGFloat finalYTop = liveY;
    BOOL foundAnimatingOut = NO;
    BOOL foundAnimatingIn = NO;
    CGFloat y = 0;
    for (iTermTipCardActionButton *actionButton in _actionButtons) {
        if (actionButton.indexInRow == 0) {
            if (actionButton.animationState == kTipCardButtonAnimatingOutCurrently) {
                // Don't mess with moving buttons. They'll be fine. A layout pass
                // must be done right after the animation begins and nothing can
                // change during it by fiat.
                continue;
            } else if (actionButton.animationState == kTipCardButtonAnimatingIn) {
                // Adjust "staging" coords.
                y = stageY;
                stageY += actionButton.frame.size.height;
                finalYTop += actionButton.frame.size.height;
                foundAnimatingIn = YES;
            } else {
                if (actionButton.animationState == kTipCardButtonAnimatingOut) {
                    // Adjust "final" (post-animation) coords.
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
        }

        // Finally, calculate the new button frame and update the button.
        if (!dry) {
            NSRect buttonFrame = actionButton.frame;
            buttonFrame.origin.y = y;
            CGFloat buttonWidth = (containerFrame.size.width - 2 * kContainerSideInset) / actionButton.numberOfButtonsInRow;
            buttonFrame.origin.x = kContainerSideInset + buttonWidth * actionButton.indexInRow;
            buttonFrame.size.width = buttonWidth;
            actionButton.frame = buttonFrame;
        }
    }

    // If animations are happening update the post-animation frames on each button
    // and on the card. Also position the fake bottom divider if one is needed.
    if (foundAnimatingOut || foundAnimatingIn) {
        CGFloat outY = finalYTop;
        CGFloat inY = liveY;

        // Update our post-animation frame.
        _postAnimationFrame = frame;

        // Move fake bottom divider.
        if (foundAnimatingOut) {
            _fakeBottomDivider.frame = NSMakeRect(1, finalYBottom, _container.frame.size.width - 2, 1);
        } else if (foundAnimatingIn) {
            _fakeBottomDivider.frame = NSMakeRect(1, liveY, _container.frame.size.width - 2, 1);
        }

        // Set post-animation frames on buttons and adjust our post-animation
        // frame for buttons in motion.
        for (iTermTipCardActionButton *actionButton in _actionButtons) {
            if (actionButton.animationState == kTipCardButtonAnimatingOut) {
                NSRect rect = actionButton.frame;
                rect.origin.y = outY;
                if (actionButton.indexInRow == 0) {
                    outY += rect.size.height;
                    _postAnimationFrame.size.height -= rect.size.height;
                }
                actionButton.postAnimationFrame = rect;
            } else if (actionButton.animationState == kTipCardButtonAnimatingIn) {
                NSRect rect = actionButton.frame;
                rect.origin.y = inY;
                if (actionButton.indexInRow == 0) {
                    inY += rect.size.height;
                    _postAnimationFrame.size.height += rect.size.height;
                }
                actionButton.postAnimationFrame = rect;
            }
        }
    } else {
        // No animation is happening so post-animation frame equals actual frame.
        _postAnimationFrame = frame;
    }

    // Return our new frame.
    return frame;
}

// Pass on a button press to our client.
- (void)buttonPressed:(id)sender {
    iTermTipCardActionButton *button = sender;
    if (button.block) {
        _currentlySelectedButton = button;
        button.block(self);
        _currentlySelectedButton = nil;
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

// Animate for a height change.
- (void)animateCardWithDuration:(CGFloat)duration
                   heightChange:(CGFloat)heightChange
              originalCardFrame:(NSRect)originalCardFrame
             postAnimationFrame:(NSRect)postAnimationFrame
                 superviewWidth:(CGFloat)superviewWidth
                          block:(void (^)(void))block {
    [CATransaction begin];
    [self retain];
    [CATransaction setCompletionBlock:^{
        self.showFakeBottomDivider = NO;
        [self hideCollapsedButtons];
        block();
        self.view.frame = postAnimationFrame;
        [self release];
    }];

    NSMutableArray *buttonsToCollapse = [NSMutableArray array];
    NSRect frame;
    // Animate bounds of card.
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"bounds"];
    NSRect startBounds = originalCardFrame;
    startBounds.origin = NSMakePoint(0, 0);
    animation.fromValue = [NSValue valueWithRect:startBounds];

    NSRect endBounds = startBounds;
    endBounds.size.height += heightChange;
    frame.origin = NSZeroPoint;
    animation.toValue = [NSValue valueWithRect:endBounds];
    animation.duration = duration;

    [self.view.layer addAnimation:animation forKey:@"bounds"];

    // Animate bounds of card's container
    CABasicAnimation* containerAnimation = [CABasicAnimation animationWithKeyPath:@"bounds"];
    startBounds = self.containerView.layer.bounds;
    containerAnimation.fromValue = [NSValue valueWithRect:startBounds];

    endBounds = startBounds;
    endBounds.size.height += heightChange;
    containerAnimation.toValue = [NSValue valueWithRect:endBounds];
    containerAnimation.duration = duration;
    [self.containerView.layer addAnimation:containerAnimation forKey:@"bounds"];

    // Animate buttons to new positions, if needed
    for (iTermTipCardActionButton *button in self.actionButtons) {
        if (button.animationState != kTipCardButtonNotAnimating) {
            // Animate the button's position
            self.showFakeBottomDivider = YES;
            animation = [CABasicAnimation animationWithKeyPath:@"position"];
            NSPoint position = button.layer.position;
            animation.fromValue = [NSValue valueWithPoint:position];
            animation.toValue = [NSValue valueWithPoint:NSMakePoint(position.x, position.y + heightChange)];
            animation.duration = duration;
            [button.layer addAnimation:animation forKey:@"position"];
            if (button.animationState == kTipCardButtonAnimatingOut) {
                [buttonsToCollapse addObject:button];
                button.animationState = kTipCardButtonAnimatingOutCurrently;
            } else {
                button.animationState = kTipCardButtonNotAnimating;
            }
        }
    }
    [CATransaction commit];

    // Now that animations are in flight, update the card's layout. It won't be visible until the
    // animations are done.
    [self layoutWithWidth:superviewWidth origin:NSZeroPoint];

    // Change button frames. Also won't be visible until animations are done. A change to hidden
    // apparently has to be doen after the transaction is committed so this goes here.
    for (iTermTipCardActionButton *button in buttonsToCollapse) {
        [button setCollapsed:YES];
    }
}

- (void)draggableBoxDidDrag:(DraggableNSBox *)box {
    if (self.didDrag) {
        self.didDrag();
    }
}

- (void)draggableBoxWillDrag:(DraggableNSBox *)box {
    if (self.willDrag) {
        self.willDrag();
    }
}

@end
