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
@property(nonatomic, readonly) BOOL isRemoteHost;

- (BOOL)isEqualToRemoteHost:(id<VT100RemoteHostReading>)other;

// Returns username@hostname.
- (NSString *)usernameAndHostname;

- (id<VT100RemoteHostReading>)doppelganger;
@end

@interface VT100RemoteHost : NSObject <IntervalTreeObject, VT100RemoteHostReading>

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithUsername:(NSString *)username hostname:(NSString *)hostname NS_DESIGNATED_INITIALIZER;

+ (instancetype)localhost;
@end
