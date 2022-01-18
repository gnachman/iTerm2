//
//  VT100Screen+Mutation.h
//  iTerm2Shared
//
//  Created by George Nachman on 12/9/21.
//

#import "VT100Screen.h"
#import "VT100Terminal.h"

#import "VT100ScreenMark.h"

@class iTermTemporaryDoubleBufferedGridController;

@protocol iTermOrderedToken;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Screen (Mutation)

@property (nonatomic, readonly) VT100Grid *mutablePrimaryGrid;
@property (nonatomic, readonly) VT100Grid *mutableAltGrid;
@property (nonatomic, readonly) LineBuffer *mutableLineBuffer;

- (void)mutResetDirty;
- (iTermTemporaryDoubleBufferedGridController * _Nullable)mutableTemporaryDoubleBuffer;
- (void)mutInjectData:(NSData *)data;
- (void)mutPerformPeriodicTriggerCheck;
- (void)mutForceCheckTriggers;

@end

NS_ASSUME_NONNULL_END
