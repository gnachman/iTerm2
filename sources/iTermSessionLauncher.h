//
//  iTermSessionLauncher.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/11/19.
//

#import <Foundation/Foundation.h>

#import "iTermController.h"

@class PTYSession;
@class Profile;
@class PseudoTerminal;

NS_ASSUME_NONNULL_BEGIN

// Creates sessions.
// It takes care of retaining itself until the completion block is called.
@interface iTermSessionLauncher : NSObject

@property (nullable, nonatomic, copy) NSString *url;

// Make the new session key? Defaults to YES
@property (nonatomic) BOOL makeKey;

// Activate the app? Only effective if `makeKey` is set. Defaults to YES.
@property (nonatomic) BOOL canActivate;

// Respect System Prefs "dock" setting to open tabs instead of new windows? Defaults to NO.
@property (nonatomic) BOOL respectTabbingMode;

// If makeSession and url are NULL, use this as the command to run.
@property (nullable, nonatomic, copy) NSString *command;

// Produces the PTYSession.
@property (nullable, nonatomic, copy) void (^makeSession)(Profile *profile, PseudoTerminal *windowController, void (^completion)(PTYSession * _Nullable));

// Early notification of session creation, possibly called before the job is launched.
@property (nullable, nonatomic, copy) void (^didCreateSession)(PTYSession * _Nullable session);

// Called on completion. ok gives whether it succeeded.
@property (nullable, nonatomic, copy) void (^completion)(BOOL ok);

// If a window is to be created, what kind of window?
// Defaults to .none.
@property (nonatomic) iTermHotkeyWindowType hotkeyWindowType;

// The newly created session.
@property (nullable, nonatomic, readonly) PTYSession *session;

// Values passed to initializer.
@property (readonly, nonatomic, readonly) Profile *profile;
@property (readonly, nonatomic, readonly) PseudoTerminal *windowController;

- (instancetype)initWithProfile:(nullable Profile *)profile
               windowController:(nullable PseudoTerminal *)windowController NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// Launch and call completion block asynchronously.
- (void)launchWithCompletion:(void (^ _Nullable)(BOOL ok))completion;

// Launch and wait until completion. If makeSession is given, it must complete synchronously.
- (void)launchAndWait;

@end

NS_ASSUME_NONNULL_END
