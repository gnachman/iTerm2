//
//  VT100RemoteHost.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

// Whether a remote host is the local machine. Decided when the host is
// reported, while the reported name and our own name reflect the same instant,
// and then frozen. It must be frozen and not recomputed from names later: the
// machine's names drift over time (mDNS can renumber MacBook-Pro-3.local to -2),
// so a later string compare is unreliable, and could even flip a real remote to
// a false localhost if our own name drifts into a collision. -isLocalhost only
// compares names as a best-effort fallback for hosts with no frozen bit.
typedef NS_ENUM(NSInteger, VT100RemoteHostLocality) {
    // Not frozen. Only older serialized data (predating this stamp) lands here;
    // -isLocalhost falls back to a best-effort name compare.
    VT100RemoteHostLocalityUnknown = 0,
    // Frozen: was the local machine when reported.
    VT100RemoteHostLocalityLocalhost,
    // Frozen: a different machine when reported (a foreign name, or reached
    // across an ssh/conductor boundary).
    VT100RemoteHostLocalityRemote,
};

NS_ASSUME_NONNULL_BEGIN

@protocol VT100RemoteHostReading<NSObject, IntervalTreeImmutableObject>
@property(nonatomic, copy, readonly, nullable) NSString *hostname;
@property(nonatomic, copy, readonly, nullable) NSString *username;

// Frozen locality stamp. Prefer this over isLocalhost when you need to
// distinguish "known remote" from "don't know" (e.g., when deciding whether
// to publish a non-null isLocalhost variable).
@property(nonatomic, readonly) VT100RemoteHostLocality localityState;

// Whether this is the local host. Uses the frozen localityState; for older data
// with no frozen bit, falls back to a best-effort name compare.
@property(nonatomic, readonly) BOOL isLocalhost;
@property(nonatomic, readonly) BOOL isRemoteHost;

- (BOOL)isEqualToRemoteHost:(nullable id<VT100RemoteHostReading>)other;

// Returns username@hostname.
- (NSString *)usernameAndHostname;

- (id<VT100RemoteHostReading>)doppelganger;
@end

@interface VT100RemoteHost : NSObject <IntervalTreeObject, VT100RemoteHostReading>

@property(nonatomic, copy, readonly) NSString *guid;

- (instancetype)init NS_UNAVAILABLE;
// Convenience: locality unknown.
- (instancetype)initWithUsername:(nullable NSString *)username hostname:(nullable NSString *)hostname;
- (instancetype)initWithUsername:(nullable NSString *)username
                        hostname:(nullable NSString *)hostname
                        locality:(VT100RemoteHostLocality)locality NS_DESIGNATED_INITIALIZER;

+ (instancetype)localhost;

// Maps a published "isLocalhost" session variable value (an NSNumber, or nil
// when unknown) to a locality. Use when constructing a VT100RemoteHost from
// session variables so it inherits the frozen locality instead of falling back
// to the fragile live-hostname compare in -isLocalhost.
+ (VT100RemoteHostLocality)localityForIsLocalhostVariableValue:(nullable id)value;
@end

NS_ASSUME_NONNULL_END
