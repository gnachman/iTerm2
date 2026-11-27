//
//  iTermToolWrapper.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "iTermToolWrapper.h"

#import "iTermToolbeltView.h"
#import "DebugLogging.h"
#import "NSImage+iTerm.h"
#import "SFSymbolEnum/SFSymbolEnum.h"

static const CGFloat kTitleHeight = 19;
static const CGFloat kMargin = 4;  // Margin between title bar and content
static const CGFloat kLeftMargin = 4;
static const CGFloat kRightMargin = 4;
static const CGFloat kBottomMargin = 8;
static const CGFloat kButtonSize = 17;
static const CGFloat kTopMargin = 3;  // Margin above title bar and close button
static const CGFloat kCloseButtonLeftMargin = 2;
static const CGFloat iTermToolWrapperCollapsedHeight = 22.0;

@implementation NSView (ToolWrapper)

- (iTermToolWrapper *)toolWrapper {
    NSView *view = self.superview.superview;
    if ([view isKindOfClass:[iTermToolWrapper class]]) {
        return (iTermToolWrapper *)view;
    } else {
        return nil;
    }
}

@end

@interface iTermToolWrapper()
@property(nonatomic, readwrite) NSView *container;
@end

@implementation iTermToolWrapper {
    NSTextField *_title;
    NSButton *_closeButton;
    // Moves the tool between the left and right toolbelts.
    NSButton *_moveButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.autoresizesSubviews = NO;
        _title = [[NSTextField alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin + kButtonSize,
                                                               0,
                                                               frame.size.width - kButtonSize - kRightMargin - kCloseButtonLeftMargin,
                                                               kTitleHeight)];
        [_title setEditable:NO];
        _title.backgroundColor = [NSColor clearColor];
        [_title setAlignment:NSTextAlignmentCenter];
        [_title setBezeled:NO];
        _title.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_title];

        NSImage *closeImage = [NSImage it_imageNamed:@"closebutton" forClass:self.class];
        _closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin, 10, kButtonSize, kButtonSize)];
        [_closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        [_closeButton setImage:closeImage];
        [_closeButton setTarget:self];
        [_closeButton setAction:@selector(close:)];
        [_closeButton setBordered:NO];
        [_closeButton setTitle:@""];
        [self addSubview:_closeButton];

        _moveButton = [[NSButton alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin + kButtonSize, 10, kButtonSize, kButtonSize)];
        [_moveButton setButtonType:NSButtonTypeMomentaryPushIn];
        [_moveButton setTarget:self];
        [_moveButton setAction:@selector(moveToOtherSide:)];
        [_moveButton setBordered:NO];
        [_moveButton setTitle:@""];
        _moveButton.imageScaling = NSImageScaleProportionallyDown;
        _moveButton.contentTintColor = [NSColor secondaryLabelColor];
        [self addSubview:_moveButton];
        [self updateMoveButton];

        _container = [[NSView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                              kTitleHeight + kMargin,
                                                              frame.size.width - kLeftMargin - kRightMargin,
                                                              frame.size.height - kTitleHeight - kMargin - kBottomMargin)];
        [self addSubview:_container];
        [self relayout];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@:%p frame=%@>", [self class], self, [NSValue valueWithRect:self.frame]];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
    [super resizeWithOldSuperviewSize:oldSize];
    [self relayout];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self relayout];
}

- (void)relayout {
    NSRect frame = [self frame];
    // The move button only makes sense when there is a left toolbelt to move to.
    _moveButton.hidden = ![iTermToolbeltView leftToolbeltIsAvailable];
    if (_moveButton.hidden) {
        const CGFloat sideMargin = kCloseButtonLeftMargin + kButtonSize;
        _title.frame = NSMakeRect(sideMargin,
                                  kTopMargin,
                                  frame.size.width - kButtonSize - kRightMargin - sideMargin,
                                  kTitleHeight - kTopMargin);
    } else {
        // Close and move buttons sit on the left; reserve the same width on the right
        // so the title stays centered.
        const CGFloat sideMargin = kCloseButtonLeftMargin + 2 * kButtonSize + 2;
        _title.frame = NSMakeRect(sideMargin,
                                  kTopMargin,
                                  MAX(0, frame.size.width - 2 * sideMargin),
                                  kTitleHeight - kTopMargin);
    }
    _closeButton.frame = NSMakeRect(kCloseButtonLeftMargin, kTopMargin, kButtonSize, kButtonSize);
    _moveButton.frame = NSMakeRect(kCloseButtonLeftMargin + kButtonSize + 2, kTopMargin, kButtonSize, kButtonSize);
    _container.frame = NSMakeRect(kLeftMargin,
                                  kTitleHeight + kMargin,
                                  MAX(0, frame.size.width - kLeftMargin - kRightMargin),
                                  MAX(0, frame.size.height - kTitleHeight - kMargin - kBottomMargin));

    NSObject<ToolbeltTool> *tool = [self tool];
    if ([tool respondsToSelector:@selector(relayout)]) {
        [tool relayout];
    }
}

- (CGFloat)minimumHeight {
    if (_collapsed) {
        return iTermToolWrapperCollapsedHeight;
    }
    return [self minimumHeightWhenExpanded];
}

- (CGFloat)minimumHeightWhenExpanded {
    return [self.tool minimumHeight] + kTitleHeight + kMargin + kBottomMargin;
}

- (void)removeToolSubviews {
    [_container removeFromSuperview];
    _container = nil;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)close:(id)sender {
    if ([_delegate haveOnlyOneTool]) {
        [_delegate hideToolbelt];
    } else {
        [_delegate toggleShowToolWithName:self.name];
    }
}

- (void)setDelegate:(id<ToolWrapperDelegate>)delegate {
    _delegate = delegate;
    [self updateMoveButton];
}

- (void)updateMoveButton {
    const BOOL onLeft = [_delegate toolWrapperIsOnLeftSide];
    NSString *description = onLeft
        ? NSLocalizedStringWithDefaultValue(@"ToolWrapper.MoveToRight", nil, [NSBundle mainBundle], @"Move to the right side", @"Tooltip for the toolbelt tool button that moves the tool to the right toolbelt")
        : NSLocalizedStringWithDefaultValue(@"ToolWrapper.MoveToLeft", nil, [NSBundle mainBundle], @"Move below the tabs", @"Tooltip for the toolbelt tool button that moves the tool to the left toolbelt, below the tab bar");
    _moveButton.image = [NSImage it_imageForSymbolName:SFSymbolGetString(onLeft ? SFSymbolArrowRightToLine : SFSymbolArrowLeftToLine)
                              accessibilityDescription:description];
    _moveButton.toolTip = description;
}

- (void)moveToOtherSide:(id)sender {
    [_delegate toolWrapperMoveToOtherSide:self];
}

- (void)setName:(NSString *)theName {
    _name = [theName copy];
    // The name doubles as an identifier so it stays English; show a localized title.
    _title.stringValue = [iTermToolbeltView localizedToolNameForToolName:theName] ?: @"";
    [self performSelector:@selector(setTitleEditable) withObject:nil afterDelay:0];
}

- (void)setTitleEditable {
    [_title setEditable:NO];
}

- (id<ToolbeltTool>)tool {
    if ([[_container subviews] count] == 0) {
        return nil;
    }
    return (id<ToolbeltTool>)[[_container subviews] firstObject];
}

- (void)setCollapsed:(BOOL)collapsed {
    if (_collapsed == collapsed) {
        return;
    }
    _collapsed = collapsed;

    if (collapsed) {
        [_container removeFromSuperview];
        NSRect frame = self.frame;
        frame.size.height = iTermToolWrapperCollapsedHeight;
        self.frame = frame;
        DLog(@"Collapse %@", self.tool);
    } else {
        NSRect frame = self.frame;
        frame.size.height = self.minimumHeight;
        self.frame = frame;
        [self addSubview:_container];
        [self relayout];
        DLog(@"Expand %@", self.tool);
    }
}

- (void)temporarilyRemoveSubviews {
    if (_collapsed) {
        return;
    }
    [_title removeFromSuperview];
    [_container removeFromSuperview];
    [_closeButton removeFromSuperview];
    [_moveButton removeFromSuperview];
}

- (void)restoreSubviews {
    if (_collapsed) {
        return;
    }
    [self addSubview:_title];
    [self addSubview:_container];
    [self addSubview:_closeButton];
    [self addSubview:_moveButton];
    [self relayout];
}

@end
