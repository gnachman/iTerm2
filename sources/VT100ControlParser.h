//
//  VT100ControlParser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "CVector.h"
#import "VT100Token.h"

NS_INLINE BOOL iscontrol(int c) {
    return c <= 0x1f;
}

@interface VT100ControlParser : NSObject

// If a DCS hook is present, returns a description of it for debug logging.
@property(nonatomic, readonly) NSString *hookDescription;

// Is the unique ID for the current DCS parser, if any, equal to this?
- (BOOL)shouldUnhook:(NSString *)uniqueID;

// Force the DCS parser to remove its hook (presently, that means terminating tmux integration).
- (void)unhookDCS;

- (void)parseControlWithData:(unsigned char *)datap
                     datalen:(int)datalen
                       rmlen:(int *)rmlen
                 incidentals:(CVector *)incidentals
                       token:(VT100Token *)token
                    encoding:(NSStringEncoding)encoding
                  savedState:(NSMutableDictionary *)savedState
                   dcsHooked:(BOOL *)dcsHooked;

- (void)startTmuxRecoveryMode;

@end

