//
//  iTermLaunchAPIScriptCommand.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/24/19.
//

#import "iTermLaunchAPIScriptCommand.h"
#import "iTermApplication.h"
#import "iTermApplicationDelegate.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermScriptsMenuController.h"

@implementation iTermLaunchAPIScriptCommand

- (id)performDefaultImplementation {
    NSString *scriptName = self.directParameter;
    if (!scriptName) {
        [self setScriptErrorNumber:1];
        [self setScriptErrorString:@"No script name was specified"];
        return nil;
    }
    NSArray<NSString *> *relativeFilenames = [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] allScripts];
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.stringByDeletingPathExtension isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.lastPathComponent isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename];
            return nil;
        }
    }
    for (NSString *relativeFilename in relativeFilenames) {
        if ([relativeFilename.lastPathComponent.stringByDeletingPathExtension isEqualToString:scriptName]) {
            [self launchPythonScript:relativeFilename];
            return nil;
        }
    }

    [self setScriptErrorNumber:2];
    [self setScriptErrorString:@"Script not found"];
    return nil;
}

- (void)launchPythonScript:(NSString *)script {
    [[[[iTermApplication sharedApplication] delegate] scriptsMenuController] launchScriptWithRelativePath:script
                                                                                       explicitUserAction:NO];
}

@end
