//
//  VT100ScreenState+Private.h
//  iTerm2
//
//  Created by George Nachman on 12/28/21.
//

#import "VT100ScreenMutableState.h"

extern NSString *VT100ScreenTerminalStateKeyVT100Terminal;
extern NSString *VT100ScreenTerminalStateKeySavedColors;
extern NSString *VT100ScreenTerminalStateKeyTabStops;
extern NSString *VT100ScreenTerminalStateKeyLineDrawingCharacterSets;
extern NSString *VT100ScreenTerminalStateKeyRemoteHost;
extern NSString *VT100ScreenTerminalStateKeyPath;

@class iTermFoldMark;

@interface VT100ScreenState() <VT100ScreenMutableState> {
@protected
    VT100Grid *_primaryGrid;
    VT100Grid *_altGrid;
}
- (instancetype _Nonnull)initForMutationOnQueue:(dispatch_queue_t _Nonnull)queue;
- (instancetype _Nonnull)initWithState:(VT100ScreenMutableState * _Nonnull)source
                           predecessor:(VT100ScreenState * _Nullable)predecessor;
- (NSArray<iTermFoldMark *> *)foldMarksInRange:(NSRange)absLineRange max:(NSUInteger)maxCount;

// Returns the cached last-command mark, or nil if the cache is empty. Unlike
// -lastCommandMark, this never triggers the O(n) reverseLimitEnumerator walk
// that repopulates the cache; use it when you only want to test against the
// current cached value.
- (id<VT100ScreenMarkReading> _Nullable)cachedLastCommandMark;

@end
