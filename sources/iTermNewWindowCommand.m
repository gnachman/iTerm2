//
//  iTermNewWindowCommand.m
//  iTerm2
//
//  Created by George Nachman on 8/19/14.
//
//

#import "iTermNewWindowCommand.h"
#import "iTermController.h"
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
                                                    isHotkey:NO
                                                     makeKey:YES
                                                 canActivate:YES
                                                     command:command
                                                       block:nil];
        return session.delegate.realParentWindow.window;
    }
    return nil;
}

@end
