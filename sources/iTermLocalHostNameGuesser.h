//
//  iTermLocalHostNameGuesser.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/3/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermLocalHostNameGuesser : NSObject

// Will be nil during initialization. Use callBlockWhenReady: if you must have a nonnil value.
@property (atomic, copy, readonly, nullable) NSString *name;

+ (instancetype)sharedInstance;

- (void)callBlockWhenReady:(void (^)(NSString *name))block;

@end

NS_ASSUME_NONNULL_END
