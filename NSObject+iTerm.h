//
//  NSObject+iTerm.h
//  iTerm
//
//  Created by George Nachman on 12/22/13.
//
//

#import <Foundation/Foundation.h>

@interface NSObject (iTerm)

- (void)performSelectorOnMainThread:(SEL)selector withObjects:(NSArray *)objects;
+ (void)performAfterDuration:(NSTimeInterval)duration block:(void(^)())block;

@end
