//
//  NSWorkspace+iTerm.h
//  iTerm2
//
//  Created by George Nachman on 5/11/15.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermController.h"

@interface NSWorkspace (iTerm)

// Returns a filename for a temp file. The file will be named /tmp/\(prefix)\(random stuff)\(suffix)
- (NSString *)temporaryFileNameWithPrefix:(NSString *)prefix suffix:(NSString *)suffix;

- (BOOL)it_securityAgentIsActive;
- (void)it_openURL:(NSURL *)url
            target:(NSString *)target
             style:(iTermOpenStyle)style
            window:(NSWindow *)window;
- (void)it_openURL:(NSURL *)url
            target:(NSString *)target
     configuration:(NSWorkspaceOpenConfiguration *)configuration
             style:(iTermOpenStyle)style
            window:(NSWindow *)window;
- (void)it_openURL:(NSURL *)url
            target:(NSString *)target
     configuration:(NSWorkspaceOpenConfiguration *)configuration
             style:(iTermOpenStyle)style
            upsell:(BOOL)upsell
            window:(NSWindow *)window;

- (void)it_asyncOpenURL:(NSURL *)url
                 target:(NSString *)target
          configuration:(NSWorkspaceOpenConfiguration *)configuration
                  style:(iTermOpenStyle)style
                 upsell:(BOOL)upsell
                 window:(NSWindow *)window
             completion:(void (^)(NSRunningApplication *app, NSError *error))completion;

- (NSString *)it_newToken;
- (BOOL)it_checkToken:(NSString *)token;
- (void)it_revealInFinder:(NSString *)path;
- (BOOL)it_urlIsConditionallyLocallyOpenable:(NSURL *)url;
- (BOOL)it_urlIsLocallyOpenableWithUpsell:(NSURL *)url;

@end
