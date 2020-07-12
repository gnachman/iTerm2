//
//  iTermServiceProvider.m
//  iTerm2
//
//  Created by liupeng on 08/12/2016.
//
//

#import "iTermServiceProvider.h"
#import "iTermController.h"
#import "iTermSessionLauncher.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "PseudoTerminal.h"

@implementation iTermServiceProvider

- (void)openTab:(NSPasteboard*)pasteboard userData:(NSString *)userData error:(NSError **)error {
    [self openFilesFromPasteboard:pasteboard inWindowController:[[iTermController sharedInstance] currentTerminal] allowTabs:YES];
}

- (void)openWindow:(NSPasteboard*)pasteboard userData:(NSString *)userData error:(NSError **)error {
    [self openFilesFromPasteboard:pasteboard inWindowController:nil allowTabs:NO];
}

- (void)openFilesFromPasteboard:(NSPasteboard *)pasteboard inWindowController:(PseudoTerminal *)windowController allowTabs:(BOOL)allowTabs {
    NSArray<NSURL *> *urls = [pasteboard readObjectsForClasses:@[ [NSURL class] ] options:0];
    NSArray<NSString *> *filePathArray = [urls mapWithBlock:^id(NSURL *anObject) {
        return anObject.path;
    }];
    for (NSString *path in filePathArray) {
        BOOL isDirectory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
            if (!isDirectory) {
                windowController = [self openTab:allowTabs inTerminal:windowController directory:[path stringByDeletingLastPathComponent]];
            } else {
                windowController = [self openTab:allowTabs inTerminal:windowController directory:path];
            }
        }
    }
}

- (PseudoTerminal *)openTab:(BOOL)allowTabs inTerminal:(PseudoTerminal *)windowController directory:(NSString *)path {
    __block PseudoTerminal *pseudoTerminal = windowController;
    [iTermSessionLauncher launchBookmark:nil
                              inTerminal:pseudoTerminal
                                 withURL:nil
                        hotkeyWindowType:iTermHotkeyWindowTypeNone
                                 makeKey:YES
                             canActivate:YES
                      respectTabbingMode:NO
                                 command:nil
                             makeSession:^(Profile *profile, PseudoTerminal *term, void (^makeSessionCompletion)(PTYSession *)) {
        profile = [profile dictionaryBySettingObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        profile = [profile dictionaryBySettingObject:path forKey:KEY_WORKING_DIRECTORY];
        if (allowTabs && !windowController) {
            pseudoTerminal = [[term retain] autorelease];
        }
        [term asyncCreateTabWithProfile:profile
                            withCommand:nil
                            environment:nil
                         didMakeSession:^(PTYSession *session) {
            makeSessionCompletion(session);
        }
                             completion:nil];
    }
                          didMakeSession:nil
                              completion:nil];
    return pseudoTerminal;
}

@end
