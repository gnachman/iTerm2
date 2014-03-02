//
//  VT100Parser.h
//  iTerm
//
//  Created by George Nachman on 3/2/14.
//
//

#import <Foundation/Foundation.h>
#import "VT100Token.h"

@interface VT100Parser : NSObject

@property(nonatomic, readonly) NSData *streamData;
@property(atomic, assign) NSStringEncoding encoding;

- (void)putStreamData:(const char *)buffer length:(int)length;
- (void)clearStream;

// Returns true if a new token was parsed, false if there was nothing left to do. If stray control
// characters are found, a VT100CSIIncidental* will be added to |incidentals|, which should be
// executed before the token.
- (BOOL)parseNextToken:(VT100TCC *)token incidentals:(NSMutableArray *)incidentals;

@end
