//
//  iTermBadgeConfigurationWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/21/19.
//

#import <Cocoa/Cocoa.h>

#import "ProfileModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermBadgeConfigurationWindowController : NSWindowController

- (instancetype)initWithProfile:(Profile *)profile;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithWindowNibPath:(NSString *)windowNibPath owner:(id)owner NS_UNAVAILABLE;

@property (nonatomic, copy) Profile *profile;
@property (nonatomic, readonly) Profile *profileMutations;
@property (nonatomic, readonly) BOOL ok;

@end

NS_ASSUME_NONNULL_END
