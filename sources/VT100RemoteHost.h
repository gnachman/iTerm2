//
//  VT100RemoteHost.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

@protocol VT100RemoteHostReading<NSObject, IntervalTreeImmutableObject>
@property(nonatomic, copy, readonly) NSString *hostname;
@property(nonatomic, copy, readonly) NSString *username;

// Tries to guess if this is the local host.
@property(nonatomic, readonly) BOOL isLocalhost;

- (BOOL)isEqualToRemoteHost:(id<VT100RemoteHostReading>)other;

// Returns username@hostname.
- (NSString *)usernameAndHostname;
@end

@interface VT100RemoteHost : NSObject <IntervalTreeObject, VT100RemoteHostReading>
@property(nonatomic, copy, readwrite) NSString *hostname;
@property(nonatomic, copy, readwrite) NSString *username;

+ (instancetype)localhost;
@end
