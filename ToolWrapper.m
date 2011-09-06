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
static const CGFloat kRightMargin = 14;
static const CGFloat kBottomMargin = 8;
@implementation ToolWrapper

@synthesize name;
@synthesize container = container_;

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        title_ = [[NSTextField alloc] initWithFrame:NSMakeRect(kTitleHeight, 0, frame.size.width - kTitleHeight, kTitleHeight)];
        [title_ bind:@"value" toObject:self withKeyPath:@"name" options:nil];
        [self addSubview:title_];
        [title_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
        [title_ setAlignment:NSCenterTextAlignment];
        [title_ setBackgroundColor:[NSColor windowBackgroundColor]];
        [title_ setEditable:NO];
        [title_ setBezeled:NO];
        [title_ release];
        
        NSImage *closeImage = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"closebutton"
                                                                                                      ofType:@"tif"]];
        
        closeButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kTitleHeight, kTitleHeight)];
        [closeButton_ setButtonType:NSMomentaryPushInButton];
        [closeButton_ setImage:closeImage];
        [closeButton_ setTarget:self];
        [closeButton_ setAction:@selector(close:)];
        [closeButton_ setBordered:NO];
        [closeButton_ setTitle:@""];
        [self addSubview:closeButton_];
        [closeButton_ release];

        container_ = [[NSView alloc] initWithFrame:NSMakeRect(kLeftMargin, kTitleHeight + kMargin, frame.size.width - kLeftMargin - kRightMargin, frame.size.height - kTitleHeight - kMargin - kBottomMargin)];
        [container_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [self addSubview:container_];
        [container_ release];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(someWrapperDidClose:) name:@"iTermToolWrapperDidClose" object:nil];
    }
    return self;
}

- (void)dealloc
{
    [self.name release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)bindCloseButton
{
    [closeButton_ bind:@"enabled"
              toObject:self.superview.superview
           withKeyPath:@"haveMultipleTools"
               options:nil];
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)close:(id)sender
{
    [ToolbeltView toggleShouldShowTool:self.name];
}

- (void)someWrapperDidClose
{
    if ([[[self superview] subviews] count] == 1) {
        [closeButton_ setEnabled:NO];
    }
}

@end
