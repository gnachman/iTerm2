//
//  iTermMultiServerMessageBuilder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/16/20.
//

#import <Foundation/Foundation.h>

#import "iTermMultiServerMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermMultiServerMessageBuilder: NSObject
@property (nonatomic, readonly) iTermMultiServerMessage *message;
@property (nonatomic, readonly) NSInteger length;

- (void)appendBytes:(void *)bytes length:(NSInteger)length;
- (void)setFileDescriptor:(int)fileDescriptor;
@end

NS_ASSUME_NONNULL_END
