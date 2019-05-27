//
//  iTermServiceProvider.m
//  iTerm2
//
//  Created by liupeng on 08/12/2016.
//
//

#import "iTermServiceProvider.h"
#import "iTermController.h"
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
    NSArray *filePathArray = [pasteboard propertyListForType:NSFilenamesPboardType];
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
    [[iTermController sharedInstance] launchBookmark:nil
                                          inTerminal:pseudoTerminal
                                             withURL:nil
                                    hotkeyWindowType:iTermHotkeyWindowTypeNone
                                             makeKey:YES
                                         canActivate:YES
                                  respectTabbingMode:NO
                                             command:nil
                                               block:^PTYSession *(Profile *profile, PseudoTerminal *term) {
        profile = [profile dictionaryBySettingObject:@"Yes" forKey:KEY_CUSTOM_DIRECTORY];
        profile = [profile dictionaryBySettingObject:path forKey:KEY_WORKING_DIRECTORY];
        if (allowTabs && !windowController) {
            pseudoTerminal = [[term retain] autorelease];
        }
        return [term createTabWithProfile:profile
                              withCommand:nil
                              environment:nil
                              synchronous:NO
                               completion:nil];
    }
                                         synchronous:NO
                                          completion:nil];
    return pseudoTerminal;
}

@end
