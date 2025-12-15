//
//  iTermLaunchServices.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"

@interface iTermLaunchServices : NSObject

+ (instancetype)sharedInstance;
- (void)registerForiTerm2Scheme;

- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme;
- (void)disconnectHandlerForScheme:(NSString*)scheme;

// Returns the GUID that is assigned to the scheme, even if iTerm2 isn't registered for the scheme.
- (NSString *)guidForScheme:(NSString *)scheme;

// Returns the profile that is assigned to the scheme, returning nil if iTerm2 isn't registered for
// the scheme.
- (Profile *)profileForScheme:(NSString *)scheme;

// Tries to open a file. If no app is associated with the UTI, offer the user an open panel to
// choose an application. Associate the selected app as a view and reopen, if he picks one.
- (void)openFile:(NSString *)fullPath window:(NSWindow *)window completion:(void (^)(BOOL ok))completion;
- (void)openFile:(NSString *)fullPath fragment:(NSString *)fragment target:(NSString *)target window:(NSWindow *)window completion:(void (^)(BOOL ok))completion;

- (BOOL)iTermIsDefaultForScheme:(NSString *)scheme;

#pragma mark - Default Terminal

- (void)makeITermDefaultTerminal;
- (void)makeTerminalDefaultTerminal;
- (BOOL)iTermIsDefaultTerminal;

@end
