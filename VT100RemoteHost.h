//
//  VT100RemoteHost.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@interface VT100RemoteHost : NSObject <IntervalTreeObject>
@property(nonatomic, copy) NSString *hostname;
@property(nonatomic, copy) NSString *username;

- (BOOL)isEqualToRemoteHost:(VT100RemoteHost *)other;

@end
