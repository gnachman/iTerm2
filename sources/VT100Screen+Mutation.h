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

- (void)mutResetAllDirty;
- (void)mutResetDirty;
- (void)mutHighlightRun:(VT100GridRun)run
    withForegroundColor:(NSColor *)fgColor
        backgroundColor:(NSColor *)bgColor;
- (BOOL)mutGetAndResetHasScrolled;
- (void)mutSetMaxScrollbackLines:(unsigned int)lines;
- (iTermTemporaryDoubleBufferedGridController * _Nullable)mutableTemporaryDoubleBuffer;
- (void)mutLinkTextInRange:(NSRange)range
basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                   URLCode:(unsigned int)code;
- (void)mutHighlightTextInRange:(NSRange)range
      basedAtAbsoluteLineNumber:(long long)absoluteLineNumber
                         colors:(NSDictionary *)colors;
- (void)mutInjectData:(NSData *)data;
- (void)mutPerformPeriodicTriggerCheck;
- (void)mutForceCheckTriggers;

@end

NS_ASSUME_NONNULL_END
