//
//  iTermUserDefaultsObserver.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermUserDefaultsObserver : NSObject
- (void)observeKey:(NSString *)key block:(void (^)(void))block;
@end

NS_ASSUME_NONNULL_END
