//
//  iTermAPIAuthorizationController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, iTermAPIAuthorizationSetting) {
    iTermAPIAuthorizationSettingUnknown,
    iTermAPIAuthorizationSettingPermanentlyDenied,
    iTermAPIAuthorizationSettingRecentConsent,
    iTermAPIAuthorizationSettingExpiredConsent,
};

@interface iTermAPIAuthorizationController : NSObject

// Object identifying the requester.
@property (nonatomic, readonly) id identity;

// What action must be taken before granting access, if any.
@property (nonatomic, readonly) iTermAPIAuthorizationSetting setting;

// Was the process ID identified?
@property (nonatomic, readonly) BOOL identified;

// Short name describing the requester.
@property (nonatomic, readonly) NSString *humanReadableName;

// Full command line or bundle ID of the requester.
@property (nonatomic, readonly) NSString *fullCommandOrBundleID;

- (instancetype)initWithProcessID:(pid_t)pid NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// If identified is false, this gives the reason why.
- (nullable NSString *)identificationFailureReason;

// Permanently allow/deny access to this requester.
- (void)setAllowed:(BOOL)allow;

// Reset saved state for this requester. Setting will be .Unknown next time.
- (void)removeSetting;

@end

NS_ASSUME_NONNULL_END
