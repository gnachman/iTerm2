//
//  iTermSessionFactory.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/3/18.
//

#import "iTermSessionFactory.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermProfilePreferences.h"
#import "iTermParameterPanelWindowController.h"
#import "PTYSession.h"
#import "PseudoTerminal.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermSessionFactory {
    iTermParameterPanelWindowController *_parameterPanelWindowController;
}

#pragma mark - API

// Allocate a new session and assign it a bookmark.
- (PTYSession *)newSessionWithProfile:(Profile *)profile {
    assert(profile);
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] initSynthetic:NO];

    [[aSession screen] setUnlimitedScrollback:[profile[KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[profile[KEY_SCROLLBACK_LINES] intValue]];

    // set our preferences
    [aSession setProfile:profile];
    return aSession;
}


- (PTYSession *)createSessionWithProfile:(NSDictionary *)profile
                                 withURL:(nullable NSString *)urlString
                           forObjectType:(iTermObjectType)objectType
                        serverConnection:(nullable iTermFileDescriptorServerConnection *)serverConnection
                               canPrompt:(BOOL)canPrompt
                        windowController:(PseudoTerminal *)windowController {
    DLog(@"-createSessionWithProfile:withURL:forObjectType:");
    PTYSession *aSession;

    // Initialize a new session
    aSession = [[PTYSession alloc] initSynthetic:NO];
    [[aSession screen] setUnlimitedScrollback:[profile[KEY_UNLIMITED_SCROLLBACK] boolValue]];
    [[aSession screen] setMaxScrollbackLines:[profile[KEY_SCROLLBACK_LINES] intValue]];
    // set our preferences
    [aSession setProfile:profile];
    // Add this session to our term and make it current
    [windowController addSessionInNewTab:aSession];
    if ([aSession screen]) {
        // We process the cmd to insert URL parts
        NSString *cmd = [ITAddressBookMgr bookmarkCommand:profile
                                            forObjectType:objectType];
        NSString *name = profile[KEY_NAME];
        NSURL *url = [NSURL URLWithString:urlString];

        // Grab the addressbook command
        NSDictionary *substitutions = @{ @"$$URL$$": urlString ?: @"",
                                         @"$$HOST$$": [url host] ?: @"",
                                         @"$$USER$$": [url user] ?: @"",
                                         @"$$PASSWORD$$": [url password] ?: @"",
                                         @"$$PORT$$": [url port] ? [[url port] stringValue] : @"",
                                         @"$$PATH$$": [url path] ?: @"",
                                         @"$$RES$$": [url resourceSpecifier] ?: @"" };

        // If the command or name have any $$VARS$$ not accounted for above, prompt the user for
        // substitutions.
        substitutions = [self substitutionsForCommand:cmd
                                          sessionName:name
                                    baseSubstitutions:substitutions
                                            canPrompt:canPrompt
                                               window:windowController.window];
        if (!substitutions) {
            return nil;
        }
        cmd = [cmd stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];

        NSString *pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile forObjectType:objectType];
        if ([pwd length] == 0) {
            pwd = NSHomeDirectory();
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        BOOL isUTF8 = ([iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:profile] == NSUTF8StringEncoding);

        [windowController setName:[name stringByPerformingSubstitutions:substitutions]
                       forSession:aSession];

        // Start the command
        if (serverConnection) {
            assert([iTermAdvancedSettingsModel runJobsInServers]);
            [aSession attachToServer:*serverConnection];
        } else {
            [self startProgram:cmd
                   environment:env
                        isUTF8:isUTF8
                     inSession:aSession
                 substitutions:substitutions
              windowController:windowController];
        }
    }
    return aSession;
}

#pragma mark - Private

// Returns nil if the user pressed cancel, otherwise returns a dictionary that's a supeset of |substitutions|.
- (NSDictionary *)substitutionsForCommand:(NSString *)command
                              sessionName:(NSString *)name
                        baseSubstitutions:(NSDictionary *)substitutions
                                canPrompt:(BOOL)canPrompt
                                   window:(NSWindow *)window {
    NSSet *cmdVars = [command doubleDollarVariables];
    NSSet *nameVars = [name doubleDollarVariables];
    NSMutableSet *allVars = [cmdVars mutableCopy];
    [allVars unionSet:nameVars];
    NSMutableDictionary *allSubstitutions = [substitutions mutableCopy];
    for (NSString *var in allVars) {
        if (!substitutions[var]) {
            NSString *value = [self promptForParameter:var promptingDisabled:!canPrompt inWindow:window];
            if (!value) {
                return nil;
            }
            allSubstitutions[var] = value;
        }
    }
    return allSubstitutions;
}

// Execute the bookmark command in this session.
// Used when adding a split pane.
// Execute the bookmark command in this session.
- (BOOL)runCommandInSession:(PTYSession *)aSession
                      inCwd:(NSString *)oldCWD
              forObjectType:(iTermObjectType)objectType
           windowController:(PseudoTerminal *)windowController {
    if ([aSession screen]) {
        BOOL isUTF8;
        // Grab the addressbook command
        Profile *profile = [aSession profile];
        NSString *cmd = [ITAddressBookMgr bookmarkCommand:profile
                                            forObjectType:objectType];
        NSString *name = profile[KEY_NAME];

        // Get session parameters
        NSDictionary *substitutions = [self substitutionsForCommand:cmd
                                                        sessionName:name
                                                  baseSubstitutions:@{}
                                                          canPrompt:YES
                                                             window:windowController.window];
        if (!substitutions) {
            return NO;
        }
        cmd = [cmd stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];

        name = [name stringByPerformingSubstitutions:substitutions];
        NSString *pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile
                                                     forObjectType:objectType];
        if ([pwd length] == 0) {
            if (oldCWD) {
                pwd = oldCWD;
            } else {
                pwd = NSHomeDirectory();
            }
        }
        NSDictionary *env = [NSDictionary dictionaryWithObject: pwd forKey:@"PWD"];
        isUTF8 = ([iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:profile] == NSUTF8StringEncoding);
        [windowController setName:name forSession:aSession];
        // Start the command
        [self startProgram:cmd
               environment:env
                    isUTF8:isUTF8
                 inSession:aSession
             substitutions:substitutions
          windowController:windowController];
        return YES;
    }
    return NO;
}

// Execute the given program and set the window title if it is uninitialized.
- (void)startProgram:(NSString *)command
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
           inSession:(PTYSession*)theSession
        substitutions:(NSDictionary *)substitutions
    windowController:(PseudoTerminal *)term {
    [theSession startProgram:command
                 environment:prog_env
                      isUTF8:isUTF8
               substitutions:substitutions];

    if ([[[term window] title] isEqualToString:@"Window"]) {
        [term setWindowTitle];
    }
}

- (NSString *)promptForParameter:(NSString *)name promptingDisabled:(BOOL)promptingDisabled inWindow:(nonnull NSWindow *)window {
    if (promptingDisabled) {
        return @"";
    }
    // Make the name pretty.
    name = [name stringByReplacingOccurrencesOfString:@"$$" withString:@""];
    name = [name stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    name = [name lowercaseString];
    if (name.length) {
        NSString *firstLetter = [name substringWithRange:NSMakeRange(0, 1)];
        NSString *lastLetters = [name substringFromIndex:1];
        name = [[firstLetter uppercaseString] stringByAppendingString:lastLetters];
    }
    _parameterPanelWindowController = [[iTermParameterPanelWindowController alloc] initWithWindowNibName:@"iTermParameterPanelWindowController"];
    [_parameterPanelWindowController.parameterName setStringValue:[NSString stringWithFormat:@"“%@”:", name]];
    [_parameterPanelWindowController.parameterValue setStringValue:@""];

    [window beginSheet:_parameterPanelWindowController.window completionHandler:nil];

    [NSApp runModalForWindow:_parameterPanelWindowController.window];

    [window endSheet:_parameterPanelWindowController.window];

    [_parameterPanelWindowController.window orderOut:self];

    if (_parameterPanelWindowController.canceled) {
        return nil;
    } else {
        return [_parameterPanelWindowController.parameterValue.stringValue copy];
    }
}

@end

NS_ASSUME_NONNULL_END
