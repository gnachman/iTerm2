//
//  iTermNewWindowCommand.m
//  iTerm2
//
//  Created by George Nachman on 8/19/14.
//
//

#import "iTermNewWindowCommand.h"
#import "iTermController.h"
#import "iTermHotKeyController.h"
#import "iTermProfileHotKey.h"
#import "iTermScriptingWindow.h"
#import "NSStringITerm.h"
#import "PTYSession.h"
#import "PTYTab.h"
#import "ProfileModel.h"
#import "PseudoTerminal.h"

@implementation iTermNewWindowCommand

- (id)performDefaultImplementation {
    NSString *profileName = self.directParameter;
    Profile *profile;
    if (!profileName) {
        profile = [[ProfileModel sharedInstance] defaultBookmark];
    } else {
        profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
        if (!profile) {
            [self setScriptErrorNumber:1];
            [self setScriptErrorString:[NSString stringWithFormat:@"No profile exists named '%@'",
                                        profileName]];
            return nil;
        }
    }
    if (profile) {
        NSDictionary *args = [self evaluatedArguments];
        NSString *command = args[@"command"];
        // maybe pass isUTF8 all the way through?
        PTYSession *session =
            [[iTermController sharedInstance] launchBookmark:profile
                                                  inTerminal:nil
                                                     withURL:nil
                                            hotkeyWindowType:iTermHotkeyWindowTypeNone
                                                     makeKey:YES
                                                 canActivate:YES
                                                     command:command
                                                       block:nil];
        return [iTermScriptingWindow scriptingWindowWithWindow:session.delegate.realParentWindow.window];
    }
    return nil;
}

@end

@implementation iTermNewHotkeyWindowCommand

- (id)performDefaultImplementation {
    NSString *profileName = self.directParameter;
    Profile *profile;
    if (!profileName) {
        [self setScriptErrorNumber:4];
        [self setScriptErrorString:@"No profile name was specified"];
        return nil;
    }
    profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (!profile) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:[NSString stringWithFormat:@"No profile exists named '%@'",
                                    profileName]];
        return nil;
    }

    if (!profile[KEY_GUID]) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:[NSString stringWithFormat:@"The profile '%@' is damaged.",
                                    profileName]];
        return nil;
    }

    iTermProfileHotKey *profileHotkey = [[iTermHotKeyController sharedInstance] profileHotKeyForGUID:profile[KEY_GUID]];
    if (!profileHotkey) {
        [self setScriptErrorNumber:3];
        [self setScriptErrorString:[NSString stringWithFormat:@"The profile '%@' does not have a hotkey defined.",
                                    profileName]];
        return nil;
    }
    if (profileHotkey.windowController.weaklyReferencedObject) {
        [self setScriptErrorNumber:2];
        [self setScriptErrorString:[NSString stringWithFormat:@"A hotkey window for profile '%@' already exists. Use “reveal hotkey window” instead.",
                                    profileName]];
        return nil;
    }
    [profileHotkey showHotKeyWindow];
    return profileHotkey.windowController.window;
}

@end
