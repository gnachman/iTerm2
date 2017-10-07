//
//  iTermCallWithTimeout.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/7/17.
//

#import <Foundation/Foundation.h>

@interface iTermCallWithTimeout : NSObject

+ (instancetype)instanceForIdentifier:(NSString *)identifier;

- (BOOL)executeWithTimeout:(NSTimeInterval)timeout
                     block:(void (^)(void))block;

@end
