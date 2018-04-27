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

@property (nonatomic, readonly) dispatch_queue_t queue;

- (instancetype)initWithFileDescriptor:(int)fd clientAddress:(iTermSocketAddress *)address;

// All methods methods should only be called on self.queue:
- (NSURLRequest *)readRequest;
- (BOOL)sendResponseWithCode:(int)code reason:(NSString *)reason headers:(NSDictionary *)headers;
- (void)threadSafeClose;
- (dispatch_io_t)newChannelOnQueue:(dispatch_queue_t)queue;
- (void)badRequest;
- (void)unauthorized;

// read a chunk of bytes. blocks.
- (NSMutableData *)readSynchronously;

// For testing
- (NSData *)nextByte;

@end
