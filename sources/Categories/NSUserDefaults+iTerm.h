//
//  NSUserDefaults+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/19/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSUserDefaults (iTerm)

- (void)it_addObserverForKey:(NSString *)key
                       block:(void (^)(id newValue))block;
@end

NS_ASSUME_NONNULL_END
