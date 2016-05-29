/*
 **  PTYWindow.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **      Initial code by Kiichi Kusama
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

#import "iTerm.h"
#import "FutureMethods.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermDelayedTitleSetter.h"
#import "iTermPreferences.h"
#import "PreferencePanel.h"
#import "PseudoTerminal.h"
#import "PTYWindow.h"
#import "objc/runtime.h"

#ifdef PSEUDOTERMINAL_VERBOSE_LOGGING
#define PtyLog NSLog
#else
#define PtyLog DLog
#endif

@interface NSView (PrivateTitleBarMethods)
- (NSView *)titlebarContainerView;
@end

@implementation PTYWindow {
    int blurFilter;
    double blurRadius_;
    BOOL layoutDone;

    // True while in -[NSWindow toggleFullScreen:].
    BOOL isTogglingLionFullScreen_;
    NSObject *restoreState_;
    iTermDelayedTitleSetter *_titleSetter;
    NSInteger _uniqueNumber;
}

- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag {
    self = [super initWithContentRect:contentRect styleMask:aStyle backing:bufferingType defer:flag];
    if (self) {
        [self registerForNotifications];
    }
    return self;
}

- (instancetype)initWithContentRect:(NSRect)contentRect
                          styleMask:(NSUInteger)aStyle
                            backing:(NSBackingStoreType)bufferingType
                              defer:(BOOL)flag
                             screen:(nullable NSScreen *)screen {
    self = [super initWithContentRect:contentRect
                            styleMask:aStyle
                              backing:bufferingType
                                defer:flag
                               screen:screen];
    if (self) {
        [self registerForNotifications];
    }
    return self;
}

ITERM_WEAKLY_REFERENCEABLE

- (void)iterm_dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [restoreState_ release];
    _titleSetter.window = nil;
    [_titleSetter release];
    [super dealloc];

}

- (void)registerForNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(delayedSetTitleNotification:)
                                                 name:kDelayedTitleSetterSetTitle
                                               object:self];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(performMiniaturize:)) {
        // This makes borderless windows miniaturizable.
        return ![_delegate anyFullScreen];
    } else {
        return [super validateMenuItem:item];
    }
}

- (void)performMiniaturize:(id)sender {
    if ([_delegate anyFullScreen]) {
        [super performMiniaturize:sender];
    } else {
        // NSWindow's performMiniaturize gates miniaturization on the presence of a miniaturize button.
        [self miniaturize:self];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p frame=%@ title=%@ alpha=%f isMain=%d isKey=%d isVisible=%d delegate=%p>",
            [self class],
            self,
            [NSValue valueWithRect:self.frame],
            self.title,
            self.alphaValue,
            (int)self.isMainWindow,
            (int)self.isKeyWindow,
            (int)self.isVisible,
            self.delegate];
}

- (NSString *)windowIdentifier {
    if (!_uniqueNumber) {
        static NSInteger nextUniqueNumber = 1;
        _uniqueNumber = nextUniqueNumber++;
    }
    return [NSString stringWithFormat:@"window-%ld", (long)_uniqueNumber];
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeObject:restoreState_ forKey:kPseudoTerminalStateRestorationWindowArrangementKey];
}

- (void)setRestoreState:(NSObject *)restoreState {
    [restoreState_ autorelease];
    restoreState_ = [restoreState retain];
}

- (void)enableBlur:(double)radius {
    const double kEpsilon = 0.001;
    if (blurFilter && fabs(blurRadius_ - radius) < kEpsilon) {
        return;
    }

    CGSConnectionID con = CGSMainConnectionID();
    if (!con) {
        return;
    }
    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        function(con, [self windowNumber], (int)radius);
    } else {
        NSLog(@"Couldn't get blur function");
    }
    blurRadius_ = radius;
}

- (void)disableBlur {
    CGSConnectionID con = CGSMainConnectionID();
    if (!con) {
        return;
    }

    CGSSetWindowBackgroundBlurRadiusFunction* function = GetCGSSetWindowBackgroundBlurRadiusFunction();
    if (function) {
        function(con, [self windowNumber], 0);
    } else if (blurFilter) {
        CGSRemoveWindowFilter(con, (CGSWindowID)[self windowNumber], blurFilter);
        CGSReleaseCIFilter(CGSMainConnectionID(), blurFilter);
        blurFilter = 0;
    }
}

- (id<PTYWindowDelegateProtocol>)ptyDelegate {
    return (id<PTYWindowDelegateProtocol>)[self delegate];
}

- (void)toggleFullScreen:(id)sender {
    if (![[self ptyDelegate] lionFullScreen]  &&
        ![iTermPreferences boolForKey:kPreferenceKeyLionStyleFullscren]) {
        // The user must have clicked on the toolbar arrow, but the pref is set
        // to use traditional fullscreen.
        [(id<PTYWindowDelegateProtocol>)[self delegate] toggleTraditionalFullScreenMode];
    } else {
        [super toggleFullScreen:sender];
    }
}

- (BOOL)isTogglingLionFullScreen {
    return isTogglingLionFullScreen_;
}

- (int)screenNumber {
    return [[[[self screen] deviceDescription] objectForKey:@"NSScreenNumber"] intValue];
}

- (void)smartLayout {
    PtyLog(@"enter smartLayout");
    NSEnumerator* iterator;

    int currentScreen = [self screenNumber];
    NSRect screenRect = [[self screen] visibleFrame];

    // Get a list of relevant windows, same screen & workspace
    NSMutableArray* windows = [[NSMutableArray alloc] init];
    iterator = [[[iTermController sharedInstance] terminals] objectEnumerator];
    PseudoTerminal* term;
    PtyLog(@"Begin iterating over terminals");
    while ((term = [iterator nextObject])) {
        PTYWindow* otherWindow = (PTYWindow*)[term window];
        PtyLog(@"See window %@ at %@", otherWindow, [NSValue valueWithRect:[otherWindow frame]]);
        if (otherWindow == self) {
            PtyLog(@" skip - is self");
            continue;
        }
        int otherScreen = [otherWindow screenNumber];
        if (otherScreen != currentScreen) {
            PtyLog(@" skip - screen %d vs my %d", otherScreen, currentScreen);
            continue;
        }

        if (![otherWindow isOnActiveSpace]) {
            PtyLog(@"  skip - not in active space");
            continue;
        }

        PtyLog(@" add window to array of windows");
        [windows addObject:otherWindow];
    }


    // Find the spot on screen with the lowest window intersection
    float bestIntersect = INFINITY;
    NSRect bestFrame = [self frame];

    NSRect placementRect = NSMakeRect(
        screenRect.origin.x,
        screenRect.origin.y,
        MAX(1, screenRect.size.width-[self frame].size.width),
        MAX(1, screenRect.size.height-[self frame].size.height)
    );
    PtyLog(@"PlacementRect is %@", [NSValue valueWithRect:placementRect]);

    for(int x = 0; x < placementRect.size.width/2; x += 50) {
        for(int y = 0; y < placementRect.size.height/2; y += 50) {
            PtyLog(@"Try coord %d,%d", x, y);

            NSRect testRects[4] = {[self frame]};

            // Top Left
            testRects[0].origin.x = placementRect.origin.x + x;
            testRects[0].origin.y = placementRect.origin.y + placementRect.size.height - y;

            // Top Right
            testRects[1] = testRects[0];
            testRects[1].origin.x = placementRect.origin.x + placementRect.size.width - x;

            // Bottom Left
            testRects[2] = testRects[0];
            testRects[2].origin.y = placementRect.origin.y + y;

            // Bottom Right
            testRects[3] = testRects[1];
            testRects[3].origin.y = placementRect.origin.y + y;

            for (int i = 0; i < sizeof(testRects)/sizeof(NSRect); i++) {
                PtyLog(@"compute badness of test rect %d %@", i, [NSValue valueWithRect:testRects[i]]);

                iterator = [windows objectEnumerator];
                PTYWindow* other;
                float badness = 0.0f;
                while ((other = [iterator nextObject])) {
                    NSRect otherFrame = [other frame];
                    NSRect intersection = NSIntersectionRect(testRects[i], otherFrame);
                    badness += intersection.size.width * intersection.size.height;
                    PtyLog(@"badness of %@ is %.2f", other, intersection.size.width * intersection.size.height);
                }


                char const * names[] = {"TL", "TR", "BL", "BR"};
                PtyLog(@"%s: testRect:%@, bad:%.2f",
                        names[i], NSStringFromRect(testRects[i]), badness);

                if (badness < bestIntersect) {
                    PtyLog(@"This is the best coordinate found so far");
                    bestIntersect = badness;
                    bestFrame = testRects[i];
                }

                // Shortcut if we've found an empty spot
                if (bestIntersect == 0) {
                    PtyLog(@"zero badness. Done.");
                    goto end;
                }
            }
        }
    }

end:
    [windows release];
    PtyLog(@"set frame origin to %@", [NSValue valueWithPoint:bestFrame.origin]);
    [self setFrameOrigin:bestFrame.origin];
}

- (void)setLayoutDone {
    PtyLog(@"setLayoutDone %@", [NSThread callStackSymbols]);
    layoutDone = YES;
}

- (void)makeKeyAndOrderFront:(id)sender {
    PtyLog(@"PTYWindow makeKeyAndOrderFront: layoutDone=%d %@", (int)layoutDone, [NSThread callStackSymbols]);
    if (!layoutDone) {
        PtyLog(@"try to call windowWillShowInitial");
        [self setLayoutDone];
        if ([[self delegate] respondsToSelector:@selector(windowWillShowInitial)]) {
            [[self delegate] performSelector:@selector(windowWillShowInitial)];
        } else {
            PtyLog(@"delegate %@ does not respond", [self delegate]);
        }
    }
    PtyLog(@"PTYWindow - calling makeKeyAndOrderFont, which triggers a window resize");
    PtyLog(@"The current window frame is %fx%f", [self frame].size.width, [self frame].size.height);
    [super makeKeyAndOrderFront:sender];
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (double)approximateFractionOccluded {
    NSArray *orderedWindows = [[NSApplication sharedApplication] orderedWindows];
    NSUInteger myIndex = [orderedWindows indexOfObject:self];
    if (myIndex == 0) {
        return 0;
    }
    const int kRows = 3;
    const int kCols = 3;
    typedef struct {
        NSRect rect;
        double occlusion;
    } OcclusionPart;
    OcclusionPart parts[kRows][kCols];
    NSRect myFrame = [self frame];
    NSSize partSize = NSMakeSize(myFrame.size.width / kCols, myFrame.size.height / kRows);
    for (int y = 0; y < kRows; y++) {
        for (int x = 0; x < kCols; x++) {
            parts[y][x].rect = NSMakeRect(myFrame.origin.x + x * partSize.width,
                                          myFrame.origin.y + y * partSize.height,
                                          partSize.width,
                                          partSize.height);
            parts[y][x].occlusion = 0;
        }
    }
    CGFloat pixelsInPart = partSize.width * partSize.height;

    // This loop iterates over each window in front of this one and measures
    // how much of it intersects each part of this one (a part is one 9th of
    // the window, as divded into a 3x3 grid). For each part, an occlusion
    // fraction is tracked, which is the fraction of that part which is covered
    // by another window. It's approximate because it's the maximum occlusion
    // for that part by all other windows, so it could be too low (if two
    // windows each cover different halves of a part, for example).
    CGFloat totalOcclusion = 0;
    for (NSUInteger i = 0; i < myIndex; i++) {
        NSWindow *other = orderedWindows[i];
        if ([other isMiniaturized] || other.alphaValue < 0.1) {
            // The other window is almost transparent or miniaturized, so short circuit.
            continue;
        }
        NSRect otherFrame = [other frame];
        NSRect overallIntersection = NSIntersectionRect(otherFrame, myFrame);
        if (overallIntersection.size.width < 1 &&
            overallIntersection.size.height < 1) {
            // Short circuit--there is no overlap at all.
            continue;
        }
        totalOcclusion = 0;
        for (int y = 0; y < kRows; y++) {
            for (int x = 0; x < kCols; x++) {
                if (parts[y][x].occlusion != 1) {
                    NSRect intersection = NSIntersectionRect(parts[y][x].rect, otherFrame);
                    CGFloat pixelsOfOcclusion = intersection.size.width * intersection.size.height;
                    parts[y][x].occlusion = MAX(parts[y][x].occlusion,
                                                pixelsOfOcclusion / pixelsInPart);
                }
                totalOcclusion += parts[y][x].occlusion / (kRows * kCols);
            }
        }
        if (totalOcclusion > 0.99) {
            totalOcclusion = 1;
            break;
        }
    }

    return totalOcclusion;
}

- (void)delayedSetTitle:(NSString *)title {
    if (!_titleSetter) {
        _titleSetter = [[iTermDelayedTitleSetter alloc] init];
        _titleSetter.window = self;
    }
    [_titleSetter setTitle:title];
}

#pragma mark - Notifications

- (void)delayedSetTitleNotification:(NSNotification *)notification {
    NSDictionary *userInfo = [notification userInfo];
    NSString *title = userInfo[kDelayedTitleSetterTitleKey];
    if (title) {
        self.title = title;
    }
}

@end
