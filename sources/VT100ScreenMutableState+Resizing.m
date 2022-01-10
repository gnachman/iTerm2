//
//  VT100ScreenMutableState+Resizing.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/10/22.
//

#import "VT100ScreenMutableState+Resizing.h"

#import "DebugLogging.h"
#import "iTermSelection.h"

@implementation VT100ScreenMutableState (Resizing)

- (VT100GridSize)safeSizeForSize:(VT100GridSize)proposedSize {
    VT100GridSize size;
    size.width = MAX(proposedSize.width, 1);
    size.height = MAX(proposedSize.height, 1);
    return size;
}

- (BOOL)shouldSetSizeTo:(VT100GridSize)size {
    [self.temporaryDoubleBuffer reset];

    DLog(@"Resize session to %@", VT100GridSizeDescription(size));
    DLog(@"Before:\n%@", [self.currentGrid compactLineDumpWithContinuationMarks]);
    DLog(@"Cursor at %d,%d", self.currentGrid.cursorX, self.currentGrid.cursorY);
    if (self.commandStartCoord.x != -1) {
        [self didUpdatePromptLocation];
        [self commandDidEndWithRange:self.commandRange];
        [self invalidateCommandStartCoordWithoutSideEffects];
    }
    self.lastCommandMark = nil;

    if (self.currentGrid.size.width == 0 ||
        self.currentGrid.size.height == 0 ||
        (size.width == self.currentGrid.size.width &&
         size.height == self.currentGrid.size.height)) {
        return NO;
    }
    return YES;
}

- (void)sanityCheckIntervalsFrom:(VT100GridSize)oldSize note:(NSString *)note {
#if BETA
    for (id<IntervalTreeObject> obj in [self.intervalTree allObjects]) {
        IntervalTreeEntry *entry = obj.entry;
        Interval *interval = entry.interval;
        ITBetaAssert(interval.limit >= 0, @"Bogus interval %@ after resizing from %@ to %@. Note: %@",
                     interval, VT100GridSizeDescription(oldSize), VT100GridSizeDescription(self.currentGrid.size),
                     note);
    }
#endif
}

- (void)willSetSizeWithSelection:(iTermSelection *)selection {
    if (selection.live) {
        [selection endLiveSelection];
    }
    [selection removeWindowsWithWidth:self.width];
}

// This assumes the window's height is going to change to newHeight but _state.currentGrid.size.height
// is still the "old" height. Returns the number of lines appended.
- (int)appendScreen:(VT100Grid *)grid
        toScrollback:(LineBuffer *)lineBufferToUse
      withUsedHeight:(int)usedHeight
           newHeight:(int)newHeight {
    int n;
    if (grid.size.height - newHeight >= usedHeight) {
        // Height is decreasing but pushing HEIGHT lines into the buffer would scroll all the used
        // lines off the top, leaving the cursor floating without any text. Keep all used lines that
        // fit onscreen.
        n = MAX(usedHeight, newHeight);
    } else {
        if (newHeight < grid.size.height) {
            // Screen is shrinking.
            // If possible, keep the last used line a fixed distance from the top of
            // the screen. If not, at least save all the used lines.
            n = usedHeight;
        } else {
            // Screen is not shrinking in height. New content may be brought in on top.
            n = grid.size.height;
        }
    }
    [grid appendLines:n toLineBuffer:lineBufferToUse];

    return n;
}

@end
