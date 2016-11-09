//
//  iTermHTTPConnection.h
//  iTerm2
//
//  Created by George Nachman on 11/4/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;

@interface iTermHTTPConnection : NSObject

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address;
- (NSURLRequest *)readRequest;
- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers;
- (void)close;
- (dispatch_io_t)newChannelOnQueue:(dispatch_queue_t)queue;
- (void)badRequest;
- (void)unauthorized;

// read a chunk of bytes. blocks.
- (NSMutableData *)read;

// For testing
- (NSData *)nextByte;

@end
