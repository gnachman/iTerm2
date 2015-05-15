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
#import "ProfileModel.h"

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
        [[iTermController sharedInstance] launchBookmark:profile
                                              inTerminal:nil
                                                 withURL:nil
                                                isHotkey:NO
                                                 makeKey:YES
                                                 command:command
                                                   block:nil];
    }
    return nil;
}

@end
