//
//  VT100ControlParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100ByteStream.h"
#import "VT100Token.h"

NS_INLINE BOOL iscontrol(int c) {
    return c <= 0x1f;
}

NS_INLINE BOOL isc1(int c) {
    return c >= 0x84 && c <= 0x9f;
}

@interface VT100ControlParser : NSObject

// If a DCS hook is present, returns a description of it for debug logging.
@property(nonatomic, readonly) NSString *hookDescription;

// Is the unique ID for the current DCS parser, if any, equal to this?
- (BOOL)shouldUnhook:(NSString *)uniqueID;

// Force the DCS parser to remove its hook (presently, that means terminating tmux integration).
- (void)unhookDCS;

- (void)parseControlWithConsumer:(VT100ByteStreamConsumer *)consumer
                     incidentals:(CVector *)incidentals
                           token:(VT100Token *)token
                        encoding:(NSStringEncoding)encoding
                      savedState:(NSMutableDictionary *)savedState
                       dcsHooked:(BOOL *)dcsHooked;

- (void)startTmuxRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelTmuxRecoveryMode;

- (void)startConductorRecoveryModeWithID:(NSString *)dcsID;
- (void)cancelConductorRecoveryMode;

- (BOOL)dcsHookIsSSH;

@end

