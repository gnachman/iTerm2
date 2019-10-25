//
//  iTermPasswordManagerWindowController.h
//  iTerm
//
//  Created by George Nachman on 5/14/14.
//
//

#import <Cocoa/Cocoa.h>

@protocol iTermPasswordManagerDelegate <NSObject>

- (BOOL)iTermPasswordManagerCanEnterPassword;
- (BOOL)iTermPasswordManagerCanEnterUserName;
- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast;
- (void)iTermPasswordManagerEnterUserName:(NSString *)username broadcast:(BOOL)broadcast;
- (BOOL)iTermPasswordManagerCanBroadcast;

@optional
- (void)iTermPasswordManagerWillClose;

@end

@interface iTermPasswordEntry: NSObject
@property (nonatomic, copy) NSString *accountName;
@property (nonatomic, copy) NSString *userName;
@property (nonatomic, readonly) NSString *combinedAccountNameUserName;
@end

@interface iTermPasswordManagerWindowController : NSWindowController

@property(nonatomic, assign) id<iTermPasswordManagerDelegate> delegate;

+ (NSArray<iTermPasswordEntry *> *)entriesWithFilter:(NSString *)maybeEmptyFilter;

// Re-check if the password can be entered.
- (void)update;

- (void)selectAccountName:(NSString *)name;

@end
