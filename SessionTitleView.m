//
//  SessionTitleView.m
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SessionTitleView.h"

const double kBottomMargin = 0;
static const CGFloat kButtonSize = 17;

@implementation SessionTitleView

@synthesize title = title_;
@synthesize delegate = delegate_;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const double kMargin = 5;
        double x = kMargin;
        
        NSImage *closeImage = [[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"closebutton"
                                                                                                      ofType:@"tif"]];
        closeButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(x, (frame.size.height - kButtonSize) / 2, kButtonSize, kButtonSize)];
        [closeButton_ setButtonType:NSMomentaryPushInButton];
        [closeButton_ setImage:closeImage];
        [closeButton_ setTarget:self];
        [closeButton_ setAction:@selector(close:)];
        [closeButton_ setBordered:NO];
        [closeButton_ setTitle:@""];
        [[closeButton_ cell] setHighlightsBy:NSContentsCellMask];
        [self addSubview:closeButton_];
        [closeButton_ release];

        x += closeButton_.frame.size.width + kMargin;
        menuButton_ = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 42, 16.0) pullsDown:YES];
        [(NSPopUpButtonCell *)[menuButton_ cell] setBezelStyle:NSSmallIconButtonBezelStyle];
        [[menuButton_ cell] setArrowPosition:NSPopUpArrowAtBottom];
        [menuButton_ setBordered:NO];
        [menuButton_ addItemWithTitle:@""];
        NSMenuItem *item = [menuButton_ itemAtIndex:0];
        [item setImage:[NSImage imageNamed:@"NSActionTemplate"]];
        [item setOnStateImage:nil];
        [item setMixedStateImage:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(popupWillOpen:)
                                                     name:NSPopUpButtonWillPopUpNotification
                                                   object:menuButton_];
        [menuButton_ addItemWithTitle:@"Foo"];
        [menuButton_ addItemWithTitle:@"Bar"];

        NSLog(@"menu button %@", [NSValue valueWithRect:menuButton_.frame]);
        
        menuButton_.frame = NSMakeRect(frame.size.width - menuButton_.frame.size.width - kMargin,
                                       (frame.size.height - menuButton_.frame.size.height) / 2,
                                       menuButton_.frame.size.width,
                                       menuButton_.frame.size.height);
        [menuButton_ setAutoresizingMask:NSViewMinXMargin];
        [self addSubview:menuButton_];
        
        label_ = [[[NSTextField alloc] initWithFrame:NSMakeRect(x, 0, menuButton_.frame.origin.x - x - kMargin, frame.size.height)] autorelease];
        [label_ setStringValue:@""];
        [label_ setBezeled:NO];
        [label_ setDrawsBackground:NO];
        [label_ setEditable:NO];
        [label_ setSelectable:NO];
        [label_ setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
        [label_ sizeToFit];
        NSRect lframe = label_.frame;
        lframe.origin.y += (frame.size.height - lframe.size.height) / 2 + kBottomMargin;
        lframe.size.width = menuButton_.frame.origin.x - x - kMargin;
        label_.frame = lframe;
        [self addSubview:label_];
    }
    return self;
}

- (void)dealloc
{
    [title_ release];
    [super dealloc];
}

- (void)popupWillOpen:(NSNotification *)notification
{
    NSLog(@"popupWillOpen");
    if ([notification object] == menuButton_) {
        NSLog(@"Set menu");
        NSMenu *menu = [delegate_ menu];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""] autorelease];
        [menu insertItem:item atIndex:0];
        [item setImage:[NSImage imageNamed:@"NSActionTemplate"]];
        [item setOnStateImage:nil];
        [item setMixedStateImage:nil];
        [menuButton_ setMenu:menu];
    }
}

- (void)close:(id)sender
{
    [delegate_ close];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor windowFrameColor] set];
    NSRectFill(dirtyRect);
/*
    NSGradient *aGradient = [[[NSGradient alloc] initWithStartingColor:[NSColor grayColor] endingColor:[NSColor darkGrayColor]] autorelease];
    [aGradient drawInRect:NSMakeRect(dirtyRect.origin.x, 0, dirtyRect.size.width, self.frame.size.height) angle:90];
*/
    
    [[NSColor blackColor] set];
    
    [[NSColor lightGrayColor] set];
    NSRectFill(NSMakeRect(dirtyRect.origin.x, 1, dirtyRect.size.width, 1));
    
    [[NSColor blackColor] set];
    NSRectFill(NSMakeRect(dirtyRect.origin.x, 0, dirtyRect.size.width, 1));
    NSRectFill(NSMakeRect(self.frame.size.width - 1, 0, 1, self.frame.size.height));
    
    [super drawRect:dirtyRect];
}

- (void)setTitle:(NSString *)title
{
    [label_ setStringValue:title];
    [self setNeedsDisplay:YES];
}

@end
