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

@end
