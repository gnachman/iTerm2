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
@property(nonatomic, readonly) int streamLength;

- (void)putStreamData:(const char *)buffer length:(int)length;
- (void)clearStream;

- (void)addParsedTokensToArray:(NSMutableArray *)output;

@end
