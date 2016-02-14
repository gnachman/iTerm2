//
//  iTermCommandRunner.h
//  iTerm2
//
//  Created by George Nachman on 2/10/16.
//
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermCommandRunner : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithCommand:(NSString *)command
                      arguments:(NSArray<NSString *> *)arguments NS_DESIGNATED_INITIALIZER;

- (void)runWithCompletion:(void (^)(NSData * _Nullable, int))completion;

@end

NS_ASSUME_NONNULL_END
