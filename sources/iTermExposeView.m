//
//  iTermExposeView.m
//  iTerm
//
//  Created by George Nachman on 1/19/14.
//
//

#import "iTermExposeView.h"
#import "iTermExposeGridView.h"
#import "iTermExpose.h"

@implementation iTermExposeView {
    // Not explicitly retained, but a subview.
    GlobalSearch *search_;
    iTermExposeTabView *resultView_;
    PTYSession *resultSession_;
    double prevSearchHeight_;
}

@synthesize grid = grid_;

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        search_ = [[GlobalSearch alloc] initWithNibName:@"GlobalSearch" bundle:nil];
        [search_ setDelegate:self];
        const int SEARCH_MARGIN = 10;
        [[search_ view] setFrame:NSMakeRect(SEARCH_MARGIN,
                                            [self frame].size.height - [[search_ view] frame].size.height - SEARCH_MARGIN,
                                            [[search_ view] frame].size.width,
                                            [[search_ view] frame].size.height)];
        prevSearchHeight_ = [[search_ view] frame].size.height;
        [self addSubview:[search_ view]];
    }
    return self;
}

- (void)dealloc
{
    [search_ abort];
    [search_ release];
    [super dealloc];
}

- (void)setGrid:(iTermExposeGridView*)newGrid
{
    iTermExposeGridView* oldGrid = grid_;
    // retain, change, release in case newGrid==grid_.
    [oldGrid retain];
    [oldGrid removeFromSuperview];
    [self addSubview:newGrid positioned:NSWindowBelow relativeTo:[search_ view]];
    [oldGrid release];
    grid_ = newGrid;
}

- (NSRect)searchFrame
{
    NSRect rect = [[search_ view] frame];
    double dh = prevSearchHeight_ - rect.size.height;
    rect.origin.y -= dh;
    rect.size.height += dh;
    //NSLog(@"Serach frame: %lf,%lf %lfx%lf", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
    return rect;
}

- (void)globalSearchSelectionChangedToSession:(PTYSession*)theSession
{
    [resultView_ setHasResult:NO];
    resultView_ = nil;
    resultSession_ = nil;
    PTYTab *changedTab = [theSession.delegate.realParentWindow tabForSession:theSession];
    for (iTermExposeTabView* aView in [grid_ subviews]) {
        if ([aView isKindOfClass:[iTermExposeTabView class]]) {
            PTYTab* theTab = [aView tabObject];
            if (theTab && theTab == changedTab) {
                resultView_ = aView;
                resultSession_ = theSession;
            }
            [aView setNeedsDisplay:YES];
        }
    }
    [resultView_ setHasResult:YES];
    if (resultView_) {
        [grid_ updateTab:changedTab];
    }
}

- (void)globalSearchOpenSelection
{
    [grid_ onSelection:resultView_ session:resultSession_];
}

- (void)globalSearchCanceled
{
    [[iTermExpose sharedInstance] toggleOff];
}

- (void)globalSearchViewDidResize:(NSRect)origSize
{
    // If we were called because a window closed, make sure we're up to date (there's a race where
    // GlobalSearch's notification may be run before ours).
    [[iTermExpose sharedInstance] recomputeIndices:nil];
    
    if ([search_ numResults] > 0 &&
        [[search_ view] frame].size.height <= prevSearchHeight_) {
        return;
    }
    //NSLog(@"Size changed with %d results", [search_ numResults]);
    if ([search_ numResults] > 0) {
        prevSearchHeight_ = [self frame].size.height;
    } else {
        prevSearchHeight_ = [[search_ view] frame].size.height;
    }
    
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:[[grid_ subviews] count]];
    // fill the array up with images in the wrong order just to make it large
    // enough.
    int i = 0;
    for (iTermExposeTabView* tabView in [grid_ subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [images addObject:[NSNumber numberWithInt:i]];
            i++;
        }
    }
    // now make the order correct.
    NSMutableArray* permutation = [NSMutableArray arrayWithCapacity:[[grid_ subviews] count]];
    i = 0;
    for (iTermExposeTabView* tabView in [grid_ subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            [permutation addObject:[NSNumber numberWithInt:[tabView index]]];
            i++;
            if ([tabView tabObject]) {
                [images replaceObjectAtIndex:[tabView index]
                                  withObject:[[tabView tabObject] image:NO]];
            } else {
                // TODO: test this
                [images replaceObjectAtIndex:[tabView index]
                                  withObject:[tabView image]];
            }
            //NSLog(@"Place %@ at index %d", [tabView label], [tabView index]);
        }
    }
    
    NSRect* frames = (NSRect*)calloc([images count], sizeof(NSRect));
    NSScreen* theScreen = [iTermExposeGridView exposeScreen];
    NSRect screenFrame = [theScreen visibleFrame];
    screenFrame.origin = NSZeroPoint;
    if ([search_ numResults] > 0) {
        screenFrame.origin.x = [self searchFrame].origin.x + [self searchFrame].size.width;
        screenFrame.size.width -= [self searchFrame].size.width;
    }
    [[iTermExpose sharedInstance] computeLayout:images frames:frames screenFrame:screenFrame];
    
    NSRect* permutedFrames = (NSRect*)calloc([images count], sizeof(NSRect));
    for (i = 0; i < [images count]; i++) {
        //NSLog(@"Move frame at %d to %d", [[permutation objectAtIndex:i] intValue], i);
        permutedFrames[i] = frames[[[permutation objectAtIndex:i] intValue]];
    }
    free(frames);
    [grid_ setFrames:permutedFrames screenFrame:screenFrame];
}

- (iTermExposeTabView*)resultView
{
    return resultView_;
}

- (PTYSession*)resultSession
{
    return resultSession_;
}

@end
