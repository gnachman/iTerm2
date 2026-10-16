//
//  iTermPasswordManagerWindowController.h
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const iTermPasswordManagerDidLoadAccounts;
// Post to make every open password manager window reload its accounts.
extern NSString *const kPasswordManagersShouldReloadData;

@protocol iTermPasswordManagerDelegate <NSObject>

- (BOOL)iTermPasswordManagerCanEnterPassword;
- (BOOL)iTermPasswordManagerCanEnterUserName;
- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast;
- (void)iTermPasswordManagerEnterUserName:(NSString *)username broadcast:(BOOL)broadcast;
- (BOOL)iTermPasswordManagerCanBroadcast;

@optional
- (void)iTermPasswordManagerWillClose;
- (void)iTermPasswordManagerDidClose;

@end

@interface iTermPasswordManagerWindowController : NSWindowController

@property(nonatomic, assign) id<iTermPasswordManagerDelegate> delegate;

@property(nonatomic) BOOL sendUserByDefault;
@property(nonatomic, copy) NSString *defaultAccountName;

// If set, the didSendUserName block is called after sending the username when
// the user chooses to send both username and password. You can use it to focus
// the password field. This also causes the default button to become "Enter
// User Name and Password".
@property(nonatomic, copy) void (^didSendUserName)(void);

+ (NSArray<NSString *> *)cachedCombinedAccountNames;

// Re-check if the password can be entered.
- (void)update;

- (void)selectAccountName:(NSString *)name;

// Call before showing this window again after it was closed. The new open goes through
// the same authentication as a fresh window, and rows from the previous open are cleared.
- (void)reopen;

// NO once the current open has closed or ended (for example, because authentication was
// revoked), even if the window is still on screen.
@property(nonatomic, readonly) BOOL isOpen;

@end

@interface iTermPasswordManagerPanel : NSPanel
@end

@interface iTermBrowserPasswordManagerWindowController : iTermPasswordManagerWindowController
@end

