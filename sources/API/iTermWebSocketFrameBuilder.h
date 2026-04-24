//
//  iTermWebSocketFrameBuilder.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermWebSocketFrame;

@interface iTermWebSocketFrameBuilder : NSObject
- (void)addData:(NSData *)data frame:(void (^)(iTermWebSocketFrame *, BOOL *))frameBlock;
@end
