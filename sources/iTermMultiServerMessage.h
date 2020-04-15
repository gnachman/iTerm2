//
//  iTermMultiServerMessage.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermMultiServerMessage: NSObject
@property (nonatomic, readonly) NSData *data;
@property (nonatomic, readonly) NSNumber *fileDescriptor;

- (instancetype)initWithData:(NSData *)data fileDescriptor:(NSNumber *)fileDescriptor NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
@end

NS_ASSUME_NONNULL_END
