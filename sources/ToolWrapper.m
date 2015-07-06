//
//  ToolWrapper.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolWrapper.h"

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

- (ToolWrapper *)toolWrapper {
    NSView *view = self.superview.superview;
    if ([view isKindOfClass:[ToolWrapper class]]) {
        return (ToolWrapper *)view;
    } else {
        return nil;
    }
}

@end

@implementation ToolWrapper {
    NSTextField *title_;
    NSButton *closeButton_;
    NSString *name;
    NSView *container_;
    id<ToolWrapperDelegate> delegate_;  // weak
}

@synthesize name;
@synthesize container = container_;
@synthesize delegate = delegate_;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        title_ = [[NSTextField alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin + kButtonSize,
                                                               0,
                                                               frame.size.width - kButtonSize - kRightMargin - kCloseButtonLeftMargin,
                                                               kTitleHeight)];
        [title_ setEditable:NO];
        [title_ bind:@"value" toObject:self withKeyPath:@"name" options:nil];
        title_.backgroundColor = [NSColor clearColor];
        [title_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [title_ setAlignment:NSCenterTextAlignment];
        [title_ setBezeled:NO];
        [self addSubview:title_];
        [title_ release];

        NSImage *closeImage = [NSImage imageNamed:@"closebutton"];
        closeButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(kCloseButtonLeftMargin, 10, kButtonSize, kButtonSize)];
        [closeButton_ setButtonType:NSMomentaryPushInButton];
        [closeButton_ setImage:closeImage];
        [closeButton_ setTarget:self];
        [closeButton_ setAction:@selector(close:)];
        [closeButton_ setBordered:NO];
        [closeButton_ setTitle:@""];
        [self addSubview:closeButton_];
        [closeButton_ release];

        container_ = [[[NSView alloc] initWithFrame:NSMakeRect(kLeftMargin,
                                                               kTitleHeight + kMargin,
                                                               frame.size.width - kLeftMargin - kRightMargin,
                                                               frame.size.height - kTitleHeight - kMargin - kBottomMargin)] autorelease];
        [container_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:container_];
        [self relayout];
    }
    return self;
}

- (void)dealloc {
    [name release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@>", [self class], self, [NSValue valueWithRect:self.frame]];
}

- (void)relayout {
    NSRect frame = [self frame];
    title_.frame = NSMakeRect(kCloseButtonLeftMargin + kButtonSize,
                              kTopMargin,
                              frame.size.width - kButtonSize - kRightMargin - kCloseButtonLeftMargin,
                              kTitleHeight - kTopMargin);
    closeButton_.frame = NSMakeRect(kCloseButtonLeftMargin, kTopMargin, kButtonSize, kButtonSize);
    container_.frame = NSMakeRect(kLeftMargin,
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
    [container_ removeFromSuperview];
    container_ = nil;
    [title_ unbind:@"value"];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)close:(id)sender {
    if ([delegate_ haveOnlyOneTool]) {
        [delegate_ hideToolbelt];
    } else {
        [delegate_ toggleShowToolWithName:self.name];
    }
}

- (void)setName:(NSString *)theName {
    [name autorelease];
    name = [theName copy];
    [self performSelector:@selector(setTitleEditable) withObject:nil afterDelay:0];
}

- (void)setTitleEditable {
    [title_ setEditable:NO];
}

- (NSObject<ToolbeltTool> *)tool {
    if ([[container_ subviews] count] == 0) {
        return nil;
    }
    return (NSObject<ToolbeltTool>*) [[container_ subviews] objectAtIndex:0];
}

@end
