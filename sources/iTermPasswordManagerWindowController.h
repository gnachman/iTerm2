//
//  iTermPasswordManagerWindowController.h
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import <Cocoa/Cocoa.h>

extern NSString *const iTermPasswordManagerDidLoadAccounts;

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

// If set, the didSendUserName block is called after sending the username when
// the user chooses to send both username and password. You can use it to focus
// the password field. This also causes the default button to become "Enter
// User Name and Password".
@property(nonatomic, copy) void (^didSendUserName)(void);

+ (NSArray<NSString *> *)cachedCombinedAccountNames;

// Re-check if the password can be entered.
- (void)update;

- (void)selectAccountName:(NSString *)name;

@end

@interface iTermPasswordManagerPanel : NSPanel
@end
