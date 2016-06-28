// -*- mode:objc -*-
/*
 **  iTermExpose.m
 **
 **  Copyright (c) 2011
 **
 **  Author: George Nachman
 **
 **  Project: iTerm2
 **
 **  Description: Implements an Exposé-like UI for iTerm2 tabs.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermExpose.h"
#import "FutureMethods.h"
#import "GlobalSearch.h"
#import "PTYTab.h"
#import "PseudoTerminal.h"
#import "iTermController.h"
#import "iTermExposeTabView.h"
#import "iTermExposeGridView.h"
#import "iTermExposeView.h"
#import "iTermExposeWindow.h"
#import "iTermHotKeyController.h"

const float kItermExposeThumbMargin = 25;

@interface iTermExpose () <NSWindowDelegate>
@end

@implementation iTermExpose {
    NSWindow* window_;
    iTermExposeView* view_;
}

+ (NSString*)labelForTab:(PTYTab*)aTab windowNumber:(int)i tabNumber:(int)j
{
    if (i == 0) {
        return @"Defunct Tab";
    }
    NSString* jobName = [[aTab activeSession] jobName];
    if (jobName) {
        return [NSString stringWithFormat:@"%d/%d. %@", i, j, [[aTab activeSession] name]];
    } else {
        return [NSString stringWithFormat:@"%d/%d. %@", i, j, [[aTab activeSession] name]];
    }
}

+ (iTermExpose*)sharedInstance
{
    static iTermExpose* inst;
    if (!inst) {
        inst = [[iTermExpose alloc] init];
    }
    return inst;
}

+ (void)toggle
{
    if ([iTermExpose sharedInstance]->window_) {
        [[iTermExpose sharedInstance] toggleOff];
    } else {
        [[iTermExpose sharedInstance] _toggleOn];
    }
}

+ (void)exitIfActive
{
    if ([iTermExpose sharedInstance]->window_) {
        [[iTermExpose sharedInstance] toggleOff];
    }
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // If anything changes, we exit because there isn't yet code to
        // rearrange thumbnails.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tabChangedSinceLastExpose)
                                                     name:@"iTermTabContentsChanged"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recomputeIndices:)
                                                     name:@"iTermNumberOfSessionsDidChange"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(recomputeIndices:)
                                                     name:@"iTermWindowDidClose"
                                                   object:nil];
    }
    return self;
}

- (NSWindow*)window
{
    return window_;
}

- (BOOL)isVisible
{
    return window_ != nil;
}

- (void)updateTab:(PTYTab*)theTab
{
    if (window_) {
        [[view_ grid] updateTab:theTab];
    }
}

- (void)dealloc
{
    [window_ close];
    [view_ release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [window_ close];
    [self showWindows:YES];
    window_ = nil;
    [view_ release];
    view_ = nil;
    SetSystemUIMode(kUIModeNormal, 0);
}

- (void)showWindows:(BOOL)fade
{
    iTermController* controller = [iTermController sharedInstance];
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        if ([[term window] alphaValue] == 0 && ![term isHotKeyWindow]) {
            if (fade) {
                [[[term window] animator] setAlphaValue:1];
            } else {
                [[term window] setAlphaValue:1];
            }
        }
    }
}

static int CompareFrames(const void* aPtr, const void* bPtr)
{
    const NSRect* a = (NSRect*)aPtr;
    const NSRect* b = (NSRect*)bPtr;
    if (b->origin.y > a->origin.y) {
        return 1;
    }
    if (b->origin.y < a->origin.y) {
        return -1;
    }
    if (b->origin.x > a->origin.x) {
        return -1;
    }
    if (b->origin.x < a->origin.x) {
        return 1;
    }
    return 0;
}

- (void)_sortFrames:(NSRect*)frames n:(int)n
{
    qsort(frames, n, sizeof(NSRect), CompareFrames);
}

- (void)computeLayout:(NSMutableArray *)images
               frames:(NSRect*)frames
          screenFrame:(NSRect)screenFrame
{
    /*NSLog(@"**computeLayout with screen frame %lf,%lf %lfx%lf", 
          screenFrame.origin.x,
          screenFrame.origin.y,
          screenFrame.size.width,
          screenFrame.size.height);
      */    
    float n = [images count];
    int rows = 1, cols = 1;
    const float aspectRatio = screenFrame.size.width / screenFrame.size.height;

    // Computing the optimal grid size is O(n^2). Limit the number of iterations
    // to 30^2=900.
    const int maxWindowsToOptimize = 100;
    if (n > maxWindowsToOptimize) {
        [self _squareThumbGridSize:aspectRatio
                                 n:n
                            cols_p:&cols
                            rows_p:&rows];
        float waste;
        do {
            waste = [self _layoutImages:images
                                   size:NSMakeSize(screenFrame.size.width / cols,
                                                   screenFrame.size.height / rows)
                            screenFrame:screenFrame
                                 frames:frames];
            if (isinf(waste)) {
                if (screenFrame.size.width / cols > screenFrame.size.height / rows) {
                    ++cols;
                } else {
                    ++rows;
                }
            }
        } while (isinf(waste));
        
    } else {
        [self _optimalGridSize:&cols
                        rows_p:&rows
                        frames:frames
                   screenFrame:screenFrame
                        images:images
                             n:n
          maxWindowsToOptimize:maxWindowsToOptimize];
    }
    
    [self _sortFrames:frames n:[images count]];
    for (int i = 0; i < n; i++) {
        //NSLog(@"After sorting frame %d is at %@", i, FormatRect(frames[i]));
    }
}

- (void)recomputeIndices:(NSNotification*)notification
{
    if (![self isVisible]) {
        return;
    }
    if (![[view_ grid] recomputeIndices]) {
        [self toggleOff];
    }
    NSMutableArray* allSessions = [NSMutableArray arrayWithCapacity:100];
    NSMutableArray* allTabs = [NSMutableArray arrayWithCapacity:100];
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        [allSessions addObjectsFromArray:[term allSessions]];
        [allTabs addObjectsFromArray:[term tabs]];
    }
    if ([view_ resultView] &&
        [allSessions indexOfObjectIdenticalTo:[view_ resultSession]] != NSNotFound) {
        [view_ globalSearchSelectionChangedToSession:nil];
    }
    for (iTermExposeTabView* tabView in [[view_ grid] subviews]) {
        if ([tabView isKindOfClass:[iTermExposeTabView class]]) {
            PTYTab* tab = [tabView tabObject];
            if (tab && [allTabs indexOfObjectIdenticalTo:tab] == NSNotFound) {
                [tabView setTabObject:nil];
                [[view_ grid] updateTrackingRectForView:tabView];
            }
        }
    }
}


- (NSSize)scaledImageSize:(NSSize)origSize thumbSize:(NSSize)size
{
    float scale = 1;
    if (origSize.width > size.width) {
        scale = size.width / origSize.width;
    }
    if (origSize.height * scale > size.height) {
        scale = size.height / origSize.height;
    }
    // Use floor here because when tiling images they can fit exactly into a row
    // but if they're over by a fraction the grid won't work.
    return NSMakeSize(floor(origSize.width * scale), floor(origSize.height * scale));
}

static BOOL AdvanceCell(float* x, float* y, NSRect screenFrame, NSSize size) {
    *x += size.width;
    if (*x + size.width > screenFrame.origin.x + screenFrame.size.width) {
        //NSLog(@"  would have advanced x to %lf which with size of %lf is more than screen width of %lf", (double)(*x+size.width), size.width, screenFrame.size.width);
        *x = screenFrame.origin.x;
        *y += size.height;
        if (*y + size.height > screenFrame.origin.y + screenFrame.size.height) {
            return NO;
        }
    }
    return YES;
}

- (float)_layoutImages:(NSArray*)images
                  size:(NSSize)size
           screenFrame:(NSRect)screenFrame
                frames:(NSRect*)frames
{
    //NSLog(@"Layout images in frame %lf,%lf %lfx%lf", screenFrame.origin.x, screenFrame.origin.y, screenFrame.size.width, screenFrame.size.height);
    // Slightly decrease the size in case the caller expects it to exactly divide
    // screenSize. We don't want floating point errors to have a huge effect.
    size.width--;
    size.height--;

    // Find the largest image when all images have been scaled down to thumbnail
    // size. Store the scaled sizes also.
    const int n = [images count];
    int i = 0;
    NSSize scaledSizes[n];
    NSSize maxThumbSize = NSMakeSize(0, 0);
    for (NSImage* anImage in images) {
        const NSSize origSize = [anImage size];
        scaledSizes[i] = [self scaledImageSize:origSize
                                     thumbSize:size];
        maxThumbSize = NSMakeSize(MAX(maxThumbSize.width, scaledSizes[i].width),
                                  MAX(maxThumbSize.height, scaledSizes[i].height));
        i++;
    }

    // Lay the frames out in a grid originating in the lower left.
    float x = screenFrame.origin.x;
    float y = screenFrame.origin.y;
    BOOL isOk = YES;
    const int numImages = [images count];
    for (i = 0; i < numImages; i++) {
        if (!isOk) {
            return INFINITY;
        }
        NSRect proposedRect = NSMakeRect(x,
                                         y,
                                         maxThumbSize.width,
                                         maxThumbSize.height);
        frames[i] = proposedRect;
        isOk = AdvanceCell(&x, &y, screenFrame, maxThumbSize);
    }

    // Center each row horizontally and center the collection of rows
    // vertically.
    const float verticalSpan = frames[i-1].origin.y + frames[i-1].size.height;
    const float verticalShift = (screenFrame.size.height - verticalSpan) / 2;

    for (i = 0; i < n; ) {
        int j;
        for (j = i; j < n; j++) {
            // The analyzer warning here is bogus (all frames from 0 to n-1 are initialized above).
            if (frames[j].origin.y != frames[i].origin.y) {
                break;
            }
        }
        // The analyzer warning here is bogus (all frames from 0 to n-1 are initialized above).
        const float horizontalSpan = frames[j-1].origin.x + frames[j-1].size.width - frames[i].origin.x;
        const float horizontalShift = (screenFrame.size.width - horizontalSpan) / 2;
        for (int k = i; k < j; k++) {
            frames[k].origin.x += horizontalShift;
            frames[k].origin.y += verticalShift;
        }
        i = j;
    }

    // Adjust views that overlap search view by shrinking them or eliminating
    // the cell and adding to skip, the count that must be added to the end.
    NSRect searchFrame = [view_ searchFrame];
    int skip = 0;
    for (i = 0; i + skip < n; i++) {
        if (skip) {
            frames[i] = frames[i + skip];
        }
        if (NSIntersectsRect(searchFrame, frames[i])) {
            /*NSLog(@"Frame %lf,%lf %lfx%lf intersects search frame %lf,%lf %lfx%lf.",
                  frames[i].origin.x, frames[i].origin.y, frames[i].size.width, frames[i].size.height,
                  searchFrame.origin.x, searchFrame.origin.y, searchFrame.size.width, searchFrame.size.height);
             */
            NSRect intersection = NSIntersectionRect(searchFrame, frames[i]);
            if (intersection.size.height > maxThumbSize.height / 3 ||
                maxThumbSize.height < 50) {
                ++skip;
                --i;
            } else {
                // Shorten the cell a bit.
                frames[i].size.height -= intersection.size.height;
            }
        }
    }

    if (skip == n) {
        // Not enough room for any cell!
        //NSLog(@"Warning: not enough room for any cell!");
        return INFINITY;
    }

    // Add views to the end if any had to be eliminated
    // First, set x and y to the first location after the last cell.
    if (skip) {
        x = frames[i - 1].origin.x;
        y = frames[i - 1].origin.y;
        if (!AdvanceCell(&x, &y, screenFrame, maxThumbSize)) {
            return INFINITY;
        }

        // Set new x,y coordinates for the last 'skip' cells.
        while (skip) {
            NSRect proposedRect = NSMakeRect(x,
                                             y,
                                             maxThumbSize.width,
                                             maxThumbSize.height);
            if (!AdvanceCell(&x, &y, screenFrame, maxThumbSize)) {
                return INFINITY;
            }
            if (NSIntersectsRect(searchFrame, proposedRect)) {
                continue;
            }
            frames[n-skip] = proposedRect;
            --skip;
        }
    }
    // Count up wasted space
    float availableSpace = screenFrame.size.width * screenFrame.size.height - searchFrame.size.width * searchFrame.size.height;
    for (i = 0; i < n; i++) {
        NSImage *image = [images objectAtIndex:i];
        const NSSize origSize = [image size];
        NSSize scaledSize = [self scaledImageSize:origSize
                                        thumbSize:frames[i].size];
        availableSpace -= scaledSize.width * scaledSize.height;
    }

    return availableSpace;
}

- (void)_toggleOn { 
    // Hide all open hotkey windows
    [[iTermHotKeyController sharedInstance] fastHideAllHotKeyWindows];

    // Crete parallel arrays with info needed to create subviews.
    iTermController *controller = [iTermController sharedInstance];
    NSMutableArray* images = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* tabs = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* labels = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];
    NSMutableArray* wasMaximized = [NSMutableArray arrayWithCapacity:[controller numberOfTerminals]];

    int selectedIndex = [self _populateArrays:images
                                       labels:labels
                                         tabs:tabs
                                 wasMaximized:wasMaximized
                                   controller:controller];

    NSRect* frames = (NSRect*)calloc([images count], sizeof(NSRect));

    // Figure out the right size for a thumbnail.
    NSScreen* theScreen = [iTermExposeGridView exposeScreen];
    SetSystemUIMode(kUIModeAllHidden, 0);
    NSRect screenFrame = [theScreen frame];
    screenFrame.origin = NSZeroPoint;
    // Create the window and its view.
    window_ = [[iTermExposeWindow alloc] initWithContentRect:screenFrame
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:YES
                                                      screen:theScreen];
    [window_ setDelegate:self];
    view_ = [[iTermExposeView alloc] initWithFrame:NSMakeRect(0,
                                                              0,
                                                              screenFrame.size.width,
                                                              screenFrame.size.height)];

    [self computeLayout:images
                 frames:frames
            screenFrame:NSMakeRect(0, 0, screenFrame.size.width, screenFrame.size.height)];


    // Finish setting up the view. The frames array is now owned by view_.
    [view_ setGrid:[[[iTermExposeGridView alloc] initWithFrame:NSMakeRect(0,
                                                                          0,
                                                                          screenFrame.size.width,
                                                                          screenFrame.size.height)
                                                        images:images
                                                        labels:labels
                                                          tabs:tabs
                                                        frames:frames
                                                  wasMaximized:wasMaximized
                                                      putOnTop:selectedIndex] autorelease]];
    [window_ setContentView:view_];
    [window_ setBackgroundColor:[[NSColor blackColor] colorWithAlphaComponent:0]];
    [window_ setOpaque:NO];
    
    // Note: we used to tell the hotkey window it's not a hotkey window before making this window
    // key but I can't see why.
    [window_ makeKeyAndOrderFront:self];
}

- (int)_populateArrays:(NSMutableArray *)images
                labels:(NSMutableArray *)labels
                  tabs:(NSMutableArray *)tabs
          wasMaximized:(NSMutableArray*)wasMaximized
            controller:(iTermController *)controller
{
    int selectedIndex = 0;
    for (int i = 0; i < [controller numberOfTerminals]; i++) {
        PseudoTerminal* term = [controller terminalAtIndex:i];
        int j = 0;
        for (PTYTab* aTab in [term tabs]) {
            if (term == [controller currentTerminal] &&
                aTab == [term currentTab]) {
                selectedIndex = [images count];
            }
            [wasMaximized addObject:[NSNumber numberWithBool:[aTab hasMaximizedPane]]];
            if ([aTab hasMaximizedPane]) {
                [aTab unmaximize];
            }
            [images addObject:[aTab image:NO]];
            [tabs addObject:aTab];
            NSString* label = [iTermExpose labelForTab:aTab windowNumber:i+1 tabNumber:j+1];
            [labels addObject:label];
            j++;
        }
        assert(selectedIndex >= 0);

        [[[term window] animator] setAlphaValue:0];
    }
    return selectedIndex;
}

- (void)tabChangedSinceLastExpose
{
    for (PseudoTerminal* term in [[iTermController sharedInstance] terminals]) {
        for (PTYTab* aTab in [term tabs]) {
            for (PTYSession* aSession in [aTab sessions]) {
                PTYTextView* aTextView = [aSession textview];
                if ([aTextView getAndResetChangedSinceLastExpose]) {
                    [self updateTab:aTab];
                    break;
                }
            }
        }
    }
}

- (void)toggleOff
{
    SetSystemUIMode(kUIModeNormal, 0);
    [[view_ grid] onSelection:nil session:nil];
}

- (void)_squareThumbGridSize:(float)aspectRatio n:(float)n cols_p:(int *)cols_p rows_p:(int *)rows_p
{
    /*
     We want to solve for rows, cols.

     aspectRatio * rows ~ cols
     rows * cols ~ n
     cols ~ n / rows
     aspectRatio * rows ~ n / rows
     rows^2 ~ n / aspectRatio
     rows ~ sqrt(n/aspectRatio)
     cols ~ n / rows
     */
    float rows1 = floor(n / sqrt(n / aspectRatio));
    float cols1 = ceil(n / rows1);

    float rows2 = ceil(n / sqrt(n / aspectRatio));
    float cols2 = ceil(n / rows2);

    float aspectRatio1 = cols1/rows1;
    float aspectRatio2 = cols2/rows2;

    float err1 = fabs(aspectRatio1-aspectRatio);
    float err2 = fabs(aspectRatio2-aspectRatio);
    if (err1 < err2) {
        *rows_p = rows1;
        *cols_p = cols1;
    } else {
        *rows_p = rows2;
        *cols_p = cols2;
    }
}

- (void)_optimalGridSize:(int *)cols_p rows_p:(int *)rows_p frames:(NSRect*)frames screenFrame:(NSRect)screenFrame images:(NSMutableArray *)images n:(float)n maxWindowsToOptimize:(const int)maxWindowsToOptimize
{
    const int numImages = [images count];
    NSRect tempFrames[numImages];
    // Try every possible combination of rows and columns and pick the one
    // that wastes the fewest pixels.
    float bestWaste = INFINITY;
    for (int i = 1; i <= maxWindowsToOptimize && i <= n; i++) {
        for (int j = 1; j <= maxWindowsToOptimize && (j-1)*i < n; j++) {
            if (i * j < n) {
                continue;
            }
            float wastedSpace = [self _layoutImages:images
                                               size:NSMakeSize(screenFrame.size.width / j,
                                                               screenFrame.size.height / i)
                                         screenFrame:screenFrame
                                             frames:tempFrames];
            if (wastedSpace < bestWaste) {
                bestWaste = wastedSpace;
                memcpy(frames, tempFrames, sizeof(tempFrames));
                *rows_p = i;
                *cols_p = j;
            }
        }
    }
}


@end
