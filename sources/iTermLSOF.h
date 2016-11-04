//
//  iTermLSOF.h
//  iTerm2
//
//  Created by George Nachman on 11/8/16.
//
//

#import <Foundation/Foundation.h>

@class iTermSocketAddress;

@interface iTermLSOF : NSObject

+ (pid_t)processIDWithConnectionFromAddress:(iTermSocketAddress *)socketAddress;

@end
