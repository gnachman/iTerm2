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

+ (NSArray<NSString *> *)cachedCombinedAccountNames;

// Re-check if the password can be entered.
- (void)update;

- (void)selectAccountName:(NSString *)name;

@end

@interface iTermPasswordManagerPanel : NSPanel
@end
