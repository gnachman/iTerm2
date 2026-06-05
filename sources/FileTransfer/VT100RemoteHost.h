//
//  VT100RemoteHost.h
//  iTerm
//
//  Created by George Nachman on 12/20/13.
//
//

#import <Foundation/Foundation.h>
#import "IntervalTree.h"

// Whether a remote host is the local machine. Determined once, at the moment
// the host is reported (when the reporting shell's name and gethostname() are
// contemporaneous), and then frozen. Recomputing it later by string-comparing
// the recorded hostname against the live local hostname is unreliable because
// a network change can rename the local .local host out from under us.
typedef NS_ENUM(NSInteger, VT100RemoteHostLocality) {
    // Not determined. Hosts deserialized from a format that predates the
    // stored bit land here; consumers fall back to the legacy name compare.
    VT100RemoteHostLocalityUnknown = 0,
    // Known to be the local machine when it was reported.
    VT100RemoteHostLocalityLocalhost,
    // Known to be a different machine when it was reported.
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

// Whether this is the local host. Uses localityState when known; falls back
// to a (fragile) hostname-vs-gethostname() compare when locality is unknown.
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
