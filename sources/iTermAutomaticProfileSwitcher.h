//
//  iTermAutomaticProfileSwitching.h
//  iTerm2
//
//  Created by George Nachman on 2/28/16.
//
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

// Describes all the possible state of a profile needed to restore it.
@interface iTermSavedProfile : NSObject
@property(nonatomic, copy, nullable) Profile *profile;
@property(nonatomic, copy) Profile *originalProfile;
@property(nonatomic, assign) BOOL isDivorced;
@property(nonatomic, copy, nullable) NSMutableSet *overriddenFields;
@end

// The session that uses automatic profile switching should implement this protocol.
@protocol iTermAutomaticProfileSwitcherDelegate<NSObject>
- (void)automaticProfileSwitcherLoadProfile:(iTermSavedProfile *)savedProfile;
- (Profile *)automaticProfileSwitcherCurrentProfile;
- (iTermSavedProfile *)automaticProfileSwitcherCurrentSavedProfile;
- (NSArray<Profile *> *)automaticProfileSwitcherAllProfiles;
@end

// This class encapsulates the logic needed by automatic profile switching.
@interface iTermAutomaticProfileSwitcher : NSObject

// You should set this or nothing will work.
@property(nonatomic, assign) id<iTermAutomaticProfileSwitcherDelegate> delegate;

- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithDelegate:(id<iTermAutomaticProfileSwitcherDelegate>)delegate
                      savedState:(NSDictionary *)savedState;
- (instancetype)init NS_UNAVAILABLE;

- (NSDictionary *)savedState;

// Call this when the hsotname, username, or path changes.
- (void)setHostname:(nullable NSString *)hostname
           username:(nullable NSString *)username
               path:(nullable NSString *)path;

@end

NS_ASSUME_NONNULL_END
