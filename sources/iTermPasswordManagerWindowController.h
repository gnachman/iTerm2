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
- (void)iTermPasswordManagerEnterPassword:(NSString *)password broadcast:(BOOL)broadcast;
- (BOOL)iTermPasswordManagerCanBroadcast;

@end

@interface iTermPasswordManagerWindowController : NSWindowController

@property(nonatomic, assign) id<iTermPasswordManagerDelegate> delegate;

+ (NSArray *)accountNamesWithFilter:(NSString *)filter;

// Re-check if the password can be entered.
- (void)update;

- (void)selectAccountName:(NSString *)name;

@end
