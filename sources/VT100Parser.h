//
//  VT100Parser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100Token.h"

@class VT100TmuxParser;

@interface VT100Parser : NSObject

@property(nonatomic, readonly) NSData *streamData;
@property(atomic, assign) NSStringEncoding encoding;
@property(nonatomic, readonly) int streamLength;

- (void)putStreamData:(const char *)buffer length:(int)length;
- (void)clearStream;
- (void)forceUnhookDCS:(NSString *)uniqueID;
- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelTmuxRecoveryMode;

- (NSInteger)startConductorRecoveryModeWithID:(NSString *)dcsID tree:(NSDictionary *)tree;
- (void)cancelConductorRecoveryMode;

// CVector was created for this method. Because so many VT100Token*s are created and destroyed,
// too much time is spent adjusting their retain counts. Since an iTermObjectPool is used to avoid
// alloc/dealloc calls, the retain counts aren't useful. Finally, NSMutableArray in OS 10.9 doesn't
// respect initWithCapacity: for capacities over 16.
- (void)addParsedTokensToVector:(CVector *)vector;

// Reset all state.
- (void)reset;

// Reset but preserve SSH state.
- (void)resetExceptSSH;

@end
