//
//  VT100Terminal+Testing.h
//  iTerm2
//
//  Seams into VT100Terminal's payload parsing, exposed for unit tests.
//

#import <Foundation/Foundation.h>

#import "VT100Terminal.h"

@class VT100TabStatusUpdate;

NS_ASSUME_NONNULL_BEGIN

@interface VT100Terminal (Testing)

// The tab-status update an OSC 21337 payload describes, before it reaches the
// delegate. The payload is semicolon-delimited key=value pairs; see
// -executeSetTabStatus:.
- (VT100TabStatusUpdate *)tabStatusUpdateForOSC21337Payload:(NSString *)payload
    NS_SWIFT_NAME(tabStatusUpdate(osc21337Payload:));

@end

NS_ASSUME_NONNULL_END
