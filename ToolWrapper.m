//
//  ToolWrapper.m
//  iTerm
//
//  Created by George Nachman on 9/5/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "ToolWrapper.h"
#import "ToolbeltView.h"

static const CGFloat kTitleHeight = 17;
static const CGFloat kMargin = 4;
static const CGFloat kLeftMargin = 14;
static const CGFloat kRightMargin = 4;
static const CGFloat kBottomMargin = 8;
static const CGFloat kButtonSize = 17;
@implementation ToolWrapper

@synthesize name;
@synthesize container = container_;
@synthesize term;
@synthesize delegate = delegate_;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        title_ = [[NSTextField alloc] initWithFrame:NSMakeRect(kButtonSize, 0, frame.size.width - kButtonSize - kRightMargin, kTitleHeight)];
        [title_ setEditable:NO];
        [title_ bind:@"value" toObject:self withKeyPath:@"name" options:nil];
        [title_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [title_ setAlignment:NSCenterTextAlignment];
        [title_ setBackgroundColor:[NSColor windowBackgroundColor]];
        [title_ setBezeled:NO];
        [self addSubview:title_];
        [title_ release];

        NSImage *closeImage = [[[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"closebutton"
                                                                                                       ofType:@"tif"]] autorelease];
        closeButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kButtonSize, kButtonSize)];
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
    }
    return self;
}

- (void)dealloc
{
    [name release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)relayout
{
    NSRect frame = [self frame];
    title_.frame = NSMakeRect(kButtonSize, 0, frame.size.width - kButtonSize - kRightMargin, kTitleHeight);
    closeButton_.frame = NSMakeRect(0, 0, kButtonSize, kButtonSize);
    container_.frame = NSMakeRect(kLeftMargin, kTitleHeight + kMargin, MAX(0, frame.size.width - kLeftMargin - kRightMargin), MAX(0, frame.size.height - kTitleHeight - kMargin - kBottomMargin));

    NSObject<ToolbeltTool> *tool = [self tool];
    if ([tool respondsToSelector:@selector(relayout)]) {
        [tool relayout];
    }
}

- (void)removeToolSubviews {
    [container_ removeFromSuperview];
    container_ = nil;
    [title_ unbind:@"value"];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)close:(id)sender
{
	if ([delegate_ haveOnlyOneTool]) {
		[delegate_ hideToolbelt];
	} else {
		[delegate_ toggleShowToolWithName:self.name];
	}
}

- (void)setName:(NSString *)theName
{
    [name autorelease];
    name = [theName copy];
    [self performSelector:@selector(setTitleEditable) withObject:nil afterDelay:0];
}

- (void)setTitleEditable
{
    [title_ setEditable:NO];
}

- (NSObject<ToolbeltTool> *)tool
{
    return (NSObject<ToolbeltTool>*) [[container_ subviews] objectAtIndex:0];
}

@end
