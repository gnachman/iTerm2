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
@property (nullable, nonatomic, copy) void (^completion)(PTYSession *session, BOOL ok);

// If a window is to be created, what kind of window?
// Defaults to .none.
@property (nonatomic) iTermHotkeyWindowType hotkeyWindowType;

// The newly created session.
@property (nullable, nonatomic, readonly) PTYSession *session;

// Values passed to initializer.
@property (readonly, nonatomic, readonly) Profile *profile;
@property (readonly, nonatomic, readonly) PseudoTerminal *windowController;

+ (BOOL)profileIsWellFormed:(Profile *)profile;

// These class methods are a migration path for legacy code that predates the session launcher.

// Super-flexible way to create a new window or tab. If |block| is given then it is used to add a
// new session/tab to the window; otherwise the bookmark is used in conjunction with the optional
// URL.
+ (void)launchBookmark:(nullable NSDictionary *)bookmarkData
            inTerminal:(nullable PseudoTerminal *)theTerm
               withURL:(nullable NSString *)url
      hotkeyWindowType:(iTermHotkeyWindowType)hotkeyWindowType
               makeKey:(BOOL)makeKey
           canActivate:(BOOL)canActivate
    respectTabbingMode:(BOOL)respectTabbingMode
               command:(nullable NSString *)command
           makeSession:(void (^ _Nullable)(Profile *profile, PseudoTerminal *windowController, void (^completion)(PTYSession *)))makeSession
        didMakeSession:(void (^ _Nullable)(PTYSession *))didMakeSession
            completion:(void (^ _Nullable)(PTYSession *, BOOL))completion;

+ (void)launchBookmark:(nullable NSDictionary *)bookmarkData
            inTerminal:(nullable PseudoTerminal *)theTerm
    respectTabbingMode:(BOOL)respectTabbingMode
            completion:(void (^ _Nullable)(PTYSession *session))completion;

- (instancetype)initWithProfile:(nullable Profile *)profile
               windowController:(nullable PseudoTerminal *)windowController NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

// Launch and call completion block asynchronously.
- (void)launchWithCompletion:(void (^ _Nullable)(PTYSession *session, BOOL ok))completion;

@end

NS_ASSUME_NONNULL_END
