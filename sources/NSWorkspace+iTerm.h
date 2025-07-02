//
//  NSWorkspace+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import <Cocoa/Cocoa.h>

@interface NSWorkspace (iTerm)

// Returns a filename for a temp file. The file will be named /tmp/\(prefix)\(random stuff)\(suffix)
- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix;

- (BOOL)it_securityAgentIsActive;
- (void)it_openURL:(NSURL *)url;
- (void)it_openURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration;
- (NSString *)it_newToken;
- (BOOL)it_checkToken:(NSString *)token;
- (void)it_revealInFinder:(NSString *)path;

@end
