//
//  TemporaryNumberAllocator.h
//  iTerm
//
//  Created by George Nachman on 12/26/13.
//
//

#import <Foundation/Foundation.h>

@interface TemporaryNumberAllocator : NSObject

+ (instancetype)sharedInstance;

- (int)allocateNumber;
- (void)deallocateNumber:(int)n;

@end
