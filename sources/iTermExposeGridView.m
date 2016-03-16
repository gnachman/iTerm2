//
//  iTermExposeGridView.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermExposeGridView.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "iTermExpose.h"
#import "iTermExposeTabView.h"

@implementation iTermExposeGridView {
    iTermExposeTabView* focused_;
    NSRect* frames_;
    NSImage* cache_;  // background image
}

static BOOL SizesEqual(NSSize a, NSSize b) {
    return (int)a.width == (int)b.width && (int)a.height == (int)b.height;
}

+ (NSScreen *)exposeScreen {
    return [[[NSApplication sharedApplication] keyWindow] deepestScreen];
}

- (instancetype)initWithFrame:(NSRect)frame
                       images:(NSArray*)images
                       labels:(NSArray*)labels
                         tabs:(NSArray*)tabs
                       frames:(NSRect*)frames
                 wasMaximized:(NSArray*)wasMaximized
                     putOnTop:(int)topIndex
{
    self = [super initWithFrame:frame];
    if (self) {
        NSScreen* theScreen = [iTermExposeGridView exposeScreen];
        NSRect screenFrame = [theScreen frame];
        screenFrame.origin = NSZeroPoint;
        NSRect visibleScreenFrame = [theScreen visibleFrame];
        //NSLog(@"Screen origin is %lf, %lf", screenFrame.origin.x, screenFrame.origin.y);
        frames_ = frames;
        [self setAlphaValue:0];
        [[self animator] setAlphaValue:1];
        const int n = [images count];

        iTermExposeTabView* selectedView = nil;
        for (int i = 0; i < n; i++) {
            PTYTab* theTab = [tabs objectAtIndex:i];
            NSString* theLabel = [labels objectAtIndex:i];
            NSImage* theImage = [images objectAtIndex:i];
            BOOL wasMax = [[wasMaximized objectAtIndex:i] boolValue];
            //NSLog(@"Place %@ at %lf,%lf", theLabel, frames_[i].origin.x, frames_[i].origin.y);
            iTermExposeTabView* newView = [self addTab:theTab
                                                 label:theLabel
                                                 image:theImage
                                           screenFrame:screenFrame
                                    visibleScreenFrame:visibleScreenFrame
                                                 frame:frames_[i]
                                                 index:i
                                          wasMaximized:wasMax];
            if (i == topIndex) {
                selectedView = newView;
            }
        }
        [selectedView moveToTop];
    }
    return self;
}

- (void)dealloc
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        [self removeTrackingRect:[tabView trackingRectTag]];
    }
    [cache_ release];
    free(frames_);
    [super dealloc];
}

- (iTermExposeTabView*)_tabViewForTab:(PTYTab*)theTab
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView tabObject] == theTab) {
            return tabView;
        }
    }
    return nil;
}

- (BOOL)recomputeIndices
{
    for (iTermExposeTabView* tabView in [self subviews]) {
        [tabView setDirty:YES];
    }

    BOOL anythingLeft = NO;
    int w = 0;
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        int t = 0;
        for (PTYTab* aTab in [term tabs]) {
            iTermExposeTabView* tabView = [self _tabViewForTab:aTab];
            if (tabView) {
                [tabView setWindowIndex:w tabIndex:t];
                [tabView setDirty:NO];
                anythingLeft = YES;
            }
            ++t;
        }
        ++w;
    }
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView dirty]) {
            [tabView clear];
        }
    }
    return anythingLeft;
}

- (void)setFrames:(NSRect*)frames screenFrame:(NSRect)visibleScreenFrame
{
    free(frames_);
    int i = 0;
    for (iTermExposeTabView* tabView in [self subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [[tabView animator] setFrame:frames[i]];
            //NSLog(@"setFrames: Set rect of tabview %@ to %@", [tabView label], FormatRect(frames[i]));
            [tabView setNormalFrame:frames[i]];
            NSRect zoomedFrame = [self zoomedFrame:frames[i]
                                              size:[tabView origSize]
                                visibleScreenFrame:visibleScreenFrame];
            [tabView setFullSizeFrame:zoomedFrame];
            [self performSelector:@selector(updateTrackingRectForView:)
                       withObject:tabView
                       afterDelay:[[NSAnimationContext currentContext] duration]];
            i++;
        }
    }
    frames_ = frames;
}

- (NSRect)tabOrigin:(PTYTab *)theTab visibleScreenFrame:(NSRect)visibleScreenFrame screenFrame:(NSRect)screenFrame
{
    NSRect origin = [[[theTab realParentWindow] currentTab] absoluteFrame];
    origin.origin.y -= visibleScreenFrame.origin.y;
    origin.origin.x -= visibleScreenFrame.origin.x;

    origin.origin.y -= origin.size.height + screenFrame.origin.y + kItermExposeThumbMargin;
    origin.origin.x -= kItermExposeThumbMargin;
    origin.size.width += 2*kItermExposeThumbMargin;
    origin.size.height += 2*kItermExposeThumbMargin;
    return origin;
}

- (NSSize)zoomedSize:(NSSize)origin thumbSize:(NSSize)thumbSize screenFrame:(NSRect)screenFrame
{
    NSSize origSize = origin;
    origSize.width = MAX(thumbSize.width,
                         MIN(origSize.width,
                             screenFrame.size.width * 0.9));
    origSize.height = MAX(thumbSize.height,
                          MIN(origSize.height,
                              screenFrame.size.height * 0.9));
    return origSize;
}

- (void)drawRect:(NSRect)rect
{
    if (!cache_ || !SizesEqual([cache_ size], [self frame].size)) {
        [cache_ release];
        cache_ = [[NSImage alloc] initWithSize:[self frame].size];
        [cache_ lockFocus];
        // Can't use alpha 0 because clicks would pass through to windows below.
        NSGradient* aGradient = [[[NSGradient alloc]
                                  initWithStartingColor:[[NSColor blackColor] colorWithAlphaComponent:0.1]
                                  endingColor:[[NSColor blackColor] colorWithAlphaComponent:0.7]] autorelease];
        [aGradient drawInRect:[self frame] relativeCenterPosition:NSMakePoint(0, 0)];
        [cache_ unlockFocus];
    }

    [cache_ drawAtPoint:rect.origin
               fromRect:rect
              operation:NSCompositeSourceOver
               fraction:1];
}

- (NSRect)zoomedFrame:(NSRect)dest size:(NSSize)origSize visibleScreenFrame:(NSRect)visibleScreenFrame
{
    NSPoint center = NSMakePoint(dest.origin.x + dest.size.width / 2,
                                 dest.origin.y + dest.size.height / 2);
    NSRect fullSizeFrame = NSMakeRect(center.x - origSize.width / 2,
                                      center.y - origSize.height / 2,
                                      origSize.width,
                                      origSize.height);

    // rewrite fullSizeFrame so it fits entirely in visibleScreenFrame and is as
    // large as possible.
    double scale = 1;
    if (fullSizeFrame.size.width > visibleScreenFrame.size.width) {
        scale = MIN(scale, visibleScreenFrame.size.width / fullSizeFrame.size.width);
    }
    if (fullSizeFrame.size.height > visibleScreenFrame.size.height) {
        scale = MIN(scale, visibleScreenFrame.size.height / fullSizeFrame.size.height);
    }
    fullSizeFrame.size.width = round(fullSizeFrame.size.width * scale);
    fullSizeFrame.size.height  = round(fullSizeFrame.size.height * scale);

    fullSizeFrame.origin.x = MAX(fullSizeFrame.origin.x,
                                 visibleScreenFrame.origin.x);
    fullSizeFrame.origin.y = MAX(fullSizeFrame.origin.y,
                                 visibleScreenFrame.origin.y);

    if (fullSizeFrame.origin.x + fullSizeFrame.size.width > visibleScreenFrame.origin.x + visibleScreenFrame.size.width) {
        fullSizeFrame.origin.x = (visibleScreenFrame.origin.x + visibleScreenFrame.size.width) - fullSizeFrame.size.width;
    }
    if (fullSizeFrame.origin.y + fullSizeFrame.size.height > visibleScreenFrame.origin.y + visibleScreenFrame.size.height) {
        fullSizeFrame.origin.y = (visibleScreenFrame.origin.y + visibleScreenFrame.size.height) - fullSizeFrame.size.height;
    }

    return fullSizeFrame;
}

- (iTermExposeTabView*)addTab:(PTYTab *)theTab
                        label:(NSString *)theLabel
                        image:(NSImage *)theImage
                  screenFrame:(NSRect)screenFrame
           visibleScreenFrame:(NSRect)visibleScreenFrame
                        frame:(NSRect)dest
                        index:(int)theIndex
                 wasMaximized:(BOOL)wasMaximized
{
    NSRect tabRect = [self tabOrigin:theTab
                  visibleScreenFrame:visibleScreenFrame
                         screenFrame:screenFrame];

    NSSize origSize = [self zoomedSize:tabRect.size
                             thumbSize:dest.size
                           screenFrame:screenFrame];

    NSRect fullSizeFrame = [self zoomedFrame:dest
                                        size:origSize
                          visibleScreenFrame:NSMakeRect(0, 0, visibleScreenFrame.size.width, visibleScreenFrame.size.height)];
    //NSLog(@"initial zoomedFrame of %@ in %@ is %@", FormatRect(dest), FormatRect(visibleScreenFrame), FormatRect(fullSizeFrame));

    iTermExposeTabView* aView = [[iTermExposeTabView alloc] initWithImage:theImage
                                                                    label:theLabel
                                                                      tab:theTab
                                                                    frame:tabRect
                                                            fullSizeFrame:fullSizeFrame
                                                              normalFrame:dest
                                                                 delegate:self
                                                                    index:theIndex
                                                             wasMaximized:wasMaximized];
    [self addSubview:aView];
    [aView release];
    [[aView animator] setFrame:dest];
    [self performSelector:@selector(viewIsReady:)
               withObject:aView
               afterDelay:[[NSAnimationContext currentContext] duration]];
    return aView;
}

- (void)updateTab:(PTYTab*)theTab
{
    NSInteger tabIndex, windowIndex;
    tabIndex = [[theTab realParentWindow] indexOfTab:theTab];
    assert(tabIndex != NSNotFound);
    windowIndex = [[[iTermController sharedInstance] terminals] indexOfObjectIdenticalTo:(PseudoTerminal *)[theTab realParentWindow]];
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            if ([aView tabIndex] == tabIndex &&
                [aView windowIndex] == windowIndex) {
                [aView setImage:[theTab image:NO]];
                [aView setLabel:[iTermExpose labelForTab:theTab
                                            windowNumber:[aView windowIndex] + 1
                                               tabNumber:[aView tabIndex] + 1]];
            }
        }
    }
}

- (void)_restoreMaximizationExceptSession:(PTYSession*)theSession
{
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            iTermExposeTabView* tabView = (iTermExposeTabView*)aView;
            if ([aView wasMaximized] && [theSession.delegate.realParentWindow tabForSession:theSession] != [tabView tab]) {
                [[tabView tab] maximize];
            }
        }
    }
}

- (void)onSelection:(iTermExposeTabView*)theView session:(PTYSession*)theSession
{
    if (theView && ![theView tabObject]) {
        return;
    }
    [self _restoreMaximizationExceptSession:theSession];
    [theView moveToTop];
    for (iTermExposeTabView* aView in [self subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            [[aView animator] setFrame:[aView originalFrame]];
        }
    }
    if (theView) {
        [[theView tabObject] setActiveSession:theSession];
    }
    [[self animator] setAlphaValue:0];
    [self performSelector:@selector(bringTabToFore:)
               withObject:theView
               afterDelay:[[NSAnimationContext currentContext] duration]];
}

- (void)bringTabToFore:(iTermExposeTabView*)theView
{
    [[iTermExpose sharedInstance] showWindows:NO];
    if (theView) {
        [theView bringTabToFore];
    } else {
        [[[iTermExpose sharedInstance] window] orderOut:self];
    }
}

- (void)updateTrackingRectForView:(iTermExposeTabView*)aView
{
    NSRect viewRect = [aView normalFrame];
    NSRect rect = [aView imageFrame:viewRect.size];
    rect.origin.x += viewRect.origin.x;
    rect.origin.y += viewRect.origin.y;

    NSTrackingRectTag oldTag = [aView trackingRectTag];
    if (oldTag) {
        [self removeTrackingRect:oldTag];
    }
    if ([aView tabObject]) {
        [aView setTrackingRectTag:[self addTrackingRect:rect
                                                  owner:self
                                               userData:aView
                                           assumeInside:NO]];
    }
}

- (void)viewIsReady:(iTermExposeTabView*)aView
{
    [aView showLabel];
    [self updateTrackingRectForView:aView];
}

- (void)mouseExited:(NSEvent *)event
{
    //NSLog(@"mouseExited:%p", focused_);
    [focused_ onMouseExit];
    for (iTermExposeTabView* aView in [self subviews]) {
        if (aView != focused_ &&
            [aView isKindOfClass:[iTermExposeTabView class]]) {
            [[aView animator] setAlphaValue:1];
        }
    }
    focused_ = nil;
}

- (void)mouseEntered:(NSEvent *)event
{
    if (!focused_) {
        focused_ = [event userData];
        //NSLog(@"mouseEntered:%p", focused_);
        [focused_ onMouseEnter];
        for (iTermExposeTabView* aView in [self subviews]) {
            if (aView != focused_ &&
                [aView isKindOfClass:[iTermExposeTabView class]]) {
                [[aView animator] setAlphaValue:0.8];
            }
        }
    }
}

- (void)mouseDown:(NSEvent *)event
{
    [[iTermExpose sharedInstance] toggleOff];
}

@end
