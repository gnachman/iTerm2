//
//  iTermLaunchServices.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermLaunchServices.h"

#import "DebugLogging.h"
#import "ITAddressBookMgr.h"

static NSString *const kUrlHandlersUserDefaultsKey = @"URLHandlersByGuid";
static NSString *const kOldStyleUrlHandlersUserDefaultsKey = @"URLHandlers";

@interface iTermLaunchServices()<NSOpenSavePanelDelegate>
@end

@implementation iTermLaunchServices {
    NSMutableDictionary *_urlHandlersByGuid;  // NSString scheme -> NSString guid
    NSURL *_currentFileUrlForOpenPanel;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        ProfileModel *profileModel = [ProfileModel sharedInstance];

        // read in the handlers by converting the index back to bookmarks
        _urlHandlersByGuid = [[NSMutableDictionary alloc] init];
        NSDictionary *tempDict = [userDefaults objectForKey:kUrlHandlersUserDefaultsKey];
        if (!tempDict) {
            // Iterate over old style url handlers (which stored bookmark by index)
            // and add guid->urlkey to urlHandlersByGuid.
            tempDict = [userDefaults objectForKey:kOldStyleUrlHandlersUserDefaultsKey];

            for (id key in tempDict) {
                int theIndex = [[tempDict objectForKey:key] intValue];
                if (theIndex >= 0 &&
                    theIndex  < [profileModel numberOfBookmarks]) {
                    NSString *guid = [[profileModel profileAtIndex:theIndex] objectForKey:KEY_GUID];
                    _urlHandlersByGuid[key] = guid;
                }
            }
        } else {
            for (id key in tempDict) {
                NSString* guid = [tempDict objectForKey:key];
                if ([profileModel indexOfProfileWithGuid:guid] >= 0) {
                    _urlHandlersByGuid[key] = guid;
                }
            }
        }
    }
    return self;
}

- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme {
    NSURL *appURL = nil;
    BOOL set = YES;

    appURL = (NSURL *)LSCopyDefaultApplicationURLForURL((CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]],
                                                        kLSRolesAll,
                                                        NULL);
    [appURL autorelease];

    if (appURL == nil) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = [NSString stringWithFormat:@"iTerm is not the default handler for %@. "
                             @"Would you like to set iTerm as the default handler?",
                             scheme];
        alert.informativeText = @"There is currently no handler.";
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        set = ([alert runModal] == NSAlertFirstButtonReturn);
    } else if (![[[NSFileManager defaultManager] displayNameAtPath:[appURL path]] isEqualToString:@"iTerm 2"]) {
        NSString *theTitle = [NSString stringWithFormat:@"iTerm is not the default handler for %@. "
                                                        @"Would you like to set iTerm as the default handler?", scheme];
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = theTitle;
        alert.informativeText = [NSString stringWithFormat:@"The current handler is: %@",
                                 [[NSFileManager defaultManager] displayNameAtPath:[appURL path]]];
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        set = ([alert runModal] == NSAlertFirstButtonReturn);
    }

    if (set) {
        _urlHandlersByGuid[scheme] = guid;
        LSSetDefaultHandlerForURLScheme((CFStringRef)scheme,
                                        (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    }
    [self updateUserDefaults];
}

- (void)registerForiTerm2Scheme {
    LSSetDefaultHandlerForURLScheme((CFStringRef)@"iterm2",
                                    (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
}


- (void)disconnectHandlerForScheme:(NSString*)scheme {
    [_urlHandlersByGuid removeObjectForKey:scheme];
    [self updateUserDefaults];
}

- (NSString *)guidForScheme:(NSString *)scheme {
    return _urlHandlersByGuid[scheme];
}

- (void)updateUserDefaults {
    [[NSUserDefaults standardUserDefaults] setObject:_urlHandlersByGuid
                                              forKey:kUrlHandlersUserDefaultsKey];
}

- (NSString *)bundleIDForDefaultHandlerForScheme:(NSString *)scheme {
    NSURL *schemeAsURL = [NSURL URLWithString:[scheme stringByAppendingString:@":"]];
    if (!schemeAsURL) {
        return nil;
    }
    NSURL *appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:schemeAsURL];
    if (!appURL) {
        return nil;
    }
    NSBundle *bundle = [NSBundle bundleWithURL:appURL];
    return bundle.bundleIdentifier;
}

- (Profile *)profileForScheme:(NSString *)scheme {
    if (![self iTermIsDefaultForScheme:scheme]) {
        return nil;
    }
    return [[ProfileModel sharedInstance] bookmarkWithGuid:[self guidForScheme:scheme]];
}

- (BOOL)pickApplicationToOpenFile:(NSString *)fullPath {
    DLog(@"Showing app open panel");
    BOOL picked = NO;
    _currentFileUrlForOpenPanel = [NSURL fileURLWithPath:fullPath];
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.delegate = self;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] == NSModalResponseOK) {
        picked = YES;
        DLog(@"Selected app has url %@", panel.URL);
        NSBundle *appBundle = [NSBundle bundleWithURL:panel.URL];
        NSString *bundleId = [appBundle bundleIdentifier];
        DLog(@"Bundle id is %@", bundleId);
        if (bundleId) {
            NSString *uti;
            NSError *error;
            if ([_currentFileUrlForOpenPanel getResourceValue:&uti forKey:NSURLTypeIdentifierKey error:&error]) {
                DLog(@"UTI is %@. Make it the default viewer.", uti);
                LSSetDefaultRoleHandlerForContentType((CFStringRef)uti,
                                                      kLSRolesViewer,
                                                      (CFStringRef)bundleId);
                _currentFileUrlForOpenPanel = nil;
            }
        }
    }
    return picked;
}

- (BOOL)offerToPickApplicationToOpenFile:(NSString *)fullPath {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    alert.messageText = [NSString stringWithFormat:@"There is no application set to open the document “%@”", [fullPath lastPathComponent]];
    alert.informativeText = @"Choose an application on your computer to open this file.";
    [alert addButtonWithTitle:@"Choose Application…"];
    [alert addButtonWithTitle:@"Cancel"];

    DLog(@"Offer to pick an app to open %@", fullPath);
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        return [self pickApplicationToOpenFile:fullPath];
    } else {
        DLog(@"Offer declined");
        return NO;
    }
}

- (BOOL)openFile:(NSString *)fullPath {
    return [self openFile:fullPath fragment:nil];
}

- (BOOL)openFile:(NSString *)fullPath fragment:(NSString *)fragment {
    DLog(@"openFile: %@ with fragment %@", fullPath, fragment);
    if (fragment) {
        NSURLComponents *components = [NSURLComponents componentsWithURL:[NSURL fileURLWithPath:fullPath]
                                                 resolvingAgainstBaseURL:NO];
        components.fragment = fragment;
        [[NSWorkspace sharedWorkspace] openURL:components.URL];
        return YES;
    }
    BOOL ok = [[NSWorkspace sharedWorkspace] openFile:fullPath];
    if (!ok && [self offerToPickApplicationToOpenFile:fullPath]) {
        DLog(@"Try to open %@ again", fullPath);
        ok = [[NSWorkspace sharedWorkspace] openFile:fullPath];
        DLog(@"ok=%d", (int)ok);
    }
    return ok;
}

#pragma mark - Default Terminal

- (void)makeITermDefaultTerminal {
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    [self setDefaultTerminal:iTermBundleId];
}

- (void)makeTerminalDefaultTerminal {
    [self setDefaultTerminal:@"com.apple.terminal"];
}

- (BOOL)iTermIsDefaultTerminal {
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    CFStringRef unixHandler = LSCopyDefaultRoleHandlerForContentType(unixExecutableContentType, kLSRolesShell);
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL result = [iTermBundleId isEqualToString:(NSString *)unixHandler];
    if (unixHandler) {
        CFRelease(unixHandler);
    }
    return result;
}

- (BOOL)iTermIsDefaultForScheme:(NSString *)scheme {
    NSString *handlerId = [self bundleIDForDefaultHandlerForScheme:scheme];
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL result = [handlerId isEqualToString:iTermBundleId] || [@"net.sourceforge.iterm" isEqualToString:iTermBundleId];
    return result;
}

- (void)setDefaultTerminal:(NSString *)bundleId {
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    LSSetDefaultRoleHandlerForContentType(unixExecutableContentType,
                                          kLSRolesShell,
                                          (CFStringRef) bundleId);
}

#pragma mark - NSOpenSavePanelDelegate

- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
    Boolean acceptsItem = NO;
    LSCanURLAcceptURL((CFURLRef)_currentFileUrlForOpenPanel,
                      (CFURLRef)url,
                      kLSRolesViewer,
                      kLSAcceptDefault,
                      &acceptsItem);
    return (BOOL)acceptsItem;
}

@end
