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

// The localized name of the app that opens url (http://example.com when url is nil), or a
// generic “Default Browser” when that can't be determined.
- (NSString *)it_defaultBrowserNameForURL:(NSURL *)url;

// Whether clicking a web link opens it in iTerm2’s built-in browser: iTerm2 is the default or
// configured browser, or the user chose to always open links in iTerm2.
- (BOOL)it_linksOpenInBuiltInBrowser:(NSURL *)url NS_SWIFT_NAME(it_linksOpenInBuiltInBrowser(_:));

// Opens url in the browser configured in advanced settings, or the system default browser, never
// in iTerm2 and never with the plugin upsell.
- (void)it_openURLInExternalBrowser:(NSURL *)url NS_SWIFT_NAME(it_openURLInExternalBrowser(_:));

// The name of the browser it_openURLInExternalBrowser: opens url with.
- (NSString *)it_externalBrowserNameForURL:(NSURL *)url NS_SWIFT_NAME(it_externalBrowserName(for:));

// Whether it_openURLInExternalBrowser: would hand url back to iTerm2 itself.
- (BOOL)it_externalBrowserIsITerm2ForURL:(NSURL *)url NS_SWIFT_NAME(it_externalBrowserIsITerm2(for:));

@end
