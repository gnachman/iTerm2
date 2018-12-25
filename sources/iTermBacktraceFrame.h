//
//  iTermBacktraceFrame.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/24/18.
//

#import <Foundation/Foundation.h>
#include <execinfo.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermBacktraceFrame : NSObject
@property (nonatomic, readonly, nullable) NSString *stringValue;

- (instancetype)initWithString:(nullable NSString *)string NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
