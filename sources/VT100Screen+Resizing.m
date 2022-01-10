//
//  VT100Screen+Resizing.m
//  iTerm2Shared
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100Screen+Resizing.h"
#import "VT100Screen+Mutation.h"
#import "VT100Screen+Private.h"
#import "VT100ScreenMutableState+Resizing.h"

#import "DebugLogging.h"
#import "VT100RemoteHost.h"
#import "VT100WorkingDirectory.h"
#import "iTermImageMark.h"
#import "iTermSelection.h"
#import "iTermURLMark.h"

@implementation VT100Screen (Resizing)

- (void)mutSetSize:(VT100GridSize)proposedSize
      visibleLines:(VT100GridRange)previouslyVisibleLineRange
         selection:(iTermSelection *)selection
           hasView:(BOOL)hasView {
    assert([NSThread isMainThread]);

    [_mutableState performBlockWithJoinedThreads:^(VT100Terminal * _Nonnull terminal,
                                                   VT100ScreenMutableState *mutableState,
                                                   id<VT100ScreenDelegate>  _Nonnull delegate) {
        assert(mutableState);
        const VT100GridSize newSize = [mutableState safeSizeForSize:proposedSize];
        if (![mutableState shouldSetSizeTo:newSize]) {
            return;
        }
        [mutableState.linebuffer beginResizing];
        [mutableState reallySetSize:newSize
                       visibleLines:previouslyVisibleLineRange
                          selection:selection
                           delegate:delegate
                            hasView:hasView];
        [mutableState.linebuffer endResizing];

        if (gDebugLogging) {
            DLog(@"Notes after resizing to width=%@", @(_mutableState.width));
            for (id<IntervalTreeObject> object in _mutableState.intervalTree.allObjects) {
                if (![object isKindOfClass:[PTYAnnotation class]]) {
                    continue;
                }
                DLog(@"Note has coord range %@", VT100GridCoordRangeDescription([_mutableState coordRangeForInterval:object.entry.interval]));
            }
            DLog(@"------------ end -----------");
        }
    }];
}

- (void)mutSetWidth:(int)width preserveScreen:(BOOL)preserveScreen {
    if ([delegate_ screenShouldInitiateWindowResize] &&
        ![delegate_ screenWindowIsFullscreen]) {
        // set the column
        [delegate_ screenResizeToWidth:width
                                height:_state.currentGrid.size.height];
        if (!preserveScreen) {
            [_mutableState eraseInDisplayBeforeCursor:YES afterCursor:YES decProtect:NO];  // erase the screen
            _mutableState.currentGrid.cursorX = 0;
            _mutableState.currentGrid.cursorY = 0;
        }
    }
}



@end
