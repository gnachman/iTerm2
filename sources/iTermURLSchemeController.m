//
//  iTermURLSchemeController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "iTermURLSchemeController.h"
#import "ITAddressBookMgr.h"

static NSString *const kUrlHandlersUserDefaultsKey = @"URLHandlersByGuid";
static NSString *const kOldStyleUrlHandlersUserDefaultsKey = @"URLHandlers";

@implementation iTermURLSchemeController {
    NSMutableDictionary *_urlHandlersByGuid;  // NSString scheme -> NSString guid
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
    OSStatus err;
    BOOL set = YES;
    
    err = LSGetApplicationForURL((CFURLRef)[NSURL URLWithString:[scheme stringByAppendingString:@":"]],
                                 kLSRolesAll, NULL, (CFURLRef *)&appURL);
    if (err != noErr) {
        set = NSRunAlertPanel([NSString stringWithFormat:@"iTerm is not the default handler for %@. "
                                                         @"Would you like to set iTerm as the default handler?",
                                                         scheme],
                              @"There is currently no handler.",
                              @"OK",
                              @"Cancel",
                              nil) == NSAlertDefaultReturn;
    } else if (![[[NSFileManager defaultManager] displayNameAtPath:[appURL path]] isEqualToString:@"iTerm 2"]) {
        NSString *theTitle = [NSString stringWithFormat:@"iTerm is not the default handler for %@. "
                                                        @"Would you like to set iTerm as the default handler?", scheme];
        set = NSRunAlertPanel(theTitle,
                              @"The current handler is: %@",
                              @"OK",
                              @"Cancel",
                              nil,
                              [[NSFileManager defaultManager] displayNameAtPath:[appURL path]]) == NSAlertDefaultReturn;
    }
    
    if (set) {
        _urlHandlersByGuid[scheme] = guid;
        LSSetDefaultHandlerForURLScheme((CFStringRef)scheme,
                                        (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    }
    [self updateUserDefaults];
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

- (Profile *)profileForScheme:(NSString *)url {
    NSString* handlerId = (NSString *)LSCopyDefaultHandlerForURLScheme((CFStringRef)url);
    Profile *profile = nil;
    if ([handlerId isEqualToString:@"com.googlecode.iterm2"] ||
        [handlerId isEqualToString:@"net.sourceforge.iterm"]) {
        profile = [[ProfileModel sharedInstance] bookmarkWithGuid:[self guidForScheme:url]];
    }
    if (handlerId) {
        CFRelease(handlerId);
    }
    return profile;
}

@end
