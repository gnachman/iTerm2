//
//  iTermMultiServerMessage.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

#import "iTermClientServerProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMultiServerMessage: NSObject
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSNumber *fileDescriptor;

- (instancetype)initWithData:(NSData *)data fileDescriptor:(nullable NSNumber *)fileDescriptor NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithProtocolMessage:(const iTermClientServerProtocolMessage *)protocolMessage;
- (instancetype)initWithProtocolMessage:(const iTermClientServerProtocolMessage *)protocolMessage
                         fileDescriptor:(NSNumber *)fileDescriptor;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
