//
//  iTermToolWrapper.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "iTermToolWrapper.h"

#import "iTermToolbeltView.h"

static const CGFloat kTitleHeight = 19;
static const CGFloat kMargin = 4;  // Margin between title bar and content
static const CGFloat kLeftMargin = 4;
static const CGFloat kRightMargin = 4;
static const CGFloat kBottomMargin = 8;
static const CGFloat kButtonSize = 17;
static const CGFloat kTopMargin = 3;  // Margin above title bar and close button
static const CGFloat kCloseButtonLeftMargin = 5;

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
@property(nonatomic, readwrite, assign) NSView *container;
@end

@implementation iTermToolWrapper {
    NSTextField *_title;
    NSButton *_closeButton;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _title = [[NSTextField alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin + kButtonSize,
                                                               0,
                                                               frame.size.width - kButtonSize - kRightMargin - kCloseButtonLeftMargin,
                                                               kTitleHeight)];
        [_title setEditable:NO];
        [_title bind:@"value" toObject:self withKeyPath:@"name" options:nil];
        _title.backgroundColor = [NSColor clearColor];
        [_title setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [_title setAlignment:NSTextAlignmentCenter];
        [_title setBezeled:NO];
        [self addSubview:_title];
        [_title release];

        NSImage *closeImage = [NSImage imageNamed:@"closebutton"];
        _closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin, 10, kButtonSize, kButtonSize)];
        [_closeButton setButtonType:NSMomentaryPushInButton];
        [_closeButton setImage:closeImage];
        [_closeButton setTarget:self];
        [_closeButton setAction:@selector(close:)];
        [_closeButton setBordered:NO];
        [_closeButton setTitle:@""];
        [self addSubview:_closeButton];
        [_closeButton release];

        _container = [[[NSView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                               kTitleHeight + kMargin,
                                                               frame.size.width - kLeftMargin - kRightMargin,
                                                               frame.size.height - kTitleHeight - kMargin - kBottomMargin)] autorelease];
        [_container setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:_container];
        [self relayout];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_name release];

    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@:%p frame=%@>", [self class], self, [NSValue valueWithRect:self.frame]];
}

- (void)relayout {
    NSRect frame = [self frame];
    _title.frame = NSMakeRect(kCloseButtonLeftMargin + kButtonSize,
                              kTopMargin,
                              frame.size.width - kButtonSize - kRightMargin - kCloseButtonLeftMargin,
                              kTitleHeight - kTopMargin);
    _closeButton.frame = NSMakeRect(kCloseButtonLeftMargin, kTopMargin, kButtonSize, kButtonSize);
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
    return [self.tool minimumHeight] + kTitleHeight + kMargin + kBottomMargin;
}

- (void)removeToolSubviews {
    [_container removeFromSuperview];
    _container = nil;
    [_title unbind:@"value"];
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

- (void)setName:(NSString *)theName {
    [_name autorelease];
    _name = [theName copy];
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

@end
