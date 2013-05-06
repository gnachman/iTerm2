//
//  SessionTitleView.m
//  iTerm
//
//  Created by George Nachman on 10/21/11.
//  Copyright 2011 George Nachman. All rights reserved.
//

#import "SessionTitleView.h"

const double kBottomMargin = 0;
static const CGFloat kButtonSize = 17;

@interface NoFirstResponderButton : NSButton
@end

@implementation NoFirstResponderButton

// Sometimes the button becomes the first responder for some weird reason.
// Prevent that from happening. Bug 1924. This is just an experiment to see if it works (4/16/13)
- (BOOL)acceptsFirstResponder {
    return NO;
}

@end

@implementation SessionTitleView

@synthesize title = title_;
@synthesize delegate = delegate_;
@synthesize dimmingAmount = dimmingAmount_;

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        const double kMargin = 5;
        double x = kMargin;

        NSImage *closeImage = [[[NSImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"closebutton"
                                                                                                       ofType:@"tif"]] autorelease];
        closeButton_ = [[NoFirstResponderButton alloc] initWithFrame:NSMakeRect(x, (frame.size.height - kButtonSize) / 2, kButtonSize, kButtonSize)];
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

        menuButton_.frame = NSMakeRect(frame.size.width - menuButton_.frame.size.width - kMargin,
                                       (frame.size.height - menuButton_.frame.size.height) / 2 + 1,
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
        [label_ setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];

        NSRect lframe = label_.frame;
        lframe.origin.y += (frame.size.height - lframe.size.height) / 2 + kBottomMargin;
        lframe.size.width = menuButton_.frame.origin.x - x - kMargin;
        label_.frame = lframe;
        [self addSubview:label_];

        [self addCursorRect:NSMakeRect(0, 0, frame.size.width, frame.size.height)
                     cursor:[NSCursor arrowCursor]];
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
    if ([notification object] == menuButton_) {
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

- (NSColor *)dimmedColor:(NSColor *)origColor
{
    NSColor *color = [origColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    double r = [color redComponent];
    double g = [color greenComponent];
    double b = [color blueComponent];
    double alpha = 1 - dimmingAmount_;
    r = alpha * r + (1 - alpha) * 0.85;
    g = alpha * g + (1 - alpha) * 0.85;
    b = alpha * b + (1 - alpha) * 0.85;
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1];
}

- (NSColor *)dimmedBackgroundColor
{
    return [self dimmedColor:[NSColor windowFrameColor]];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[self dimmedBackgroundColor] set];
    NSRectFill(dirtyRect);
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

- (void)setDimmingAmount:(double)value
{
    dimmingAmount_ = value;
    [self setNeedsDisplay:YES];
    [label_ setTextColor:[self dimmedColor:[NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:1]]];
}

- (void)mouseDragged:(NSEvent *)theEvent
{
    [delegate_ beginDrag];
}

@end
