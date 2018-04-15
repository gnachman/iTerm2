//
//  NSThread+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/18.
//

#import <Foundation/Foundation.h>

@interface NSThread (iTerm)

// Only iTerm2 frames
+ (NSArray<NSString *> *)trimCallStackSymbols;

@end
