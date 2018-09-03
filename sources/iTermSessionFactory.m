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
#import "iTermScriptFunctionCall.h"
#import "NSDictionary+iTerm.h"
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

- (void)finishAttachingOrLaunchingSession:(PTYSession * _Nonnull)aSession
                                      cmd:(NSString *)cmd
                               completion:(void (^ _Nullable)(BOOL))completion
                              environment:(NSDictionary * _Nonnull)environment
                                   isUTF8:(BOOL)isUTF8
                         serverConnection:(iTermFileDescriptorServerConnection * _Nullable)serverConnection
                            substitutions:(NSDictionary *)substitutions
                         windowController:(PseudoTerminal * _Nonnull)windowController {
    DLog(@"finishAttachingOrLaunchingSession:%@ cmd:%@ environment:%@ isUTF8:%@ substitutions:%@ windowController:%@",
         aSession, cmd, environment, @(isUTF8), substitutions, windowController);

    // Start the command
    if (serverConnection) {
        assert([iTermAdvancedSettingsModel runJobsInServers]);
        [aSession attachToServer:*serverConnection];
        if (completion) {
            completion(YES);
        }
    } else {
        [self startProgram:cmd
               environment:environment
                    isUTF8:isUTF8
                 inSession:aSession
             substitutions:substitutions
          windowController:windowController
                completion:completion];
    }
}

- (BOOL)attachOrLaunchCommandInSession:(PTYSession *)aSession
                             canPrompt:(BOOL)canPrompt
                            objectType:(iTermObjectType)objectType
                      serverConnection:(iTermFileDescriptorServerConnection * _Nullable)serverConnection
                             urlString:(nullable NSString *)urlString
                          allowURLSubs:(BOOL)allowURLSubs
                           environment:(NSDictionary *)environment
                                oldCWD:(nullable NSString *)oldCWD
                        forceUseOldCWD:(BOOL)forceUseOldCWD
                               command:(nullable NSString *)command
                                isUTF8:(nullable NSNumber *)isUTF8Number
                         substitutions:(nullable NSDictionary *)providedSubs
                      windowController:(PseudoTerminal * _Nonnull)windowController
                            completion:(void (^ _Nullable)(BOOL))completion {
    DLog(@"attachOrLaunchCommandInSession:%@ canPrompt:%@ objectType:%@ urlString:%@ allowURLSubs:%@ environment:%@ oldCWD:%@ forceUseOldCWD:%@ command:%@ isUTF8:%@ substitutions:%@ windowController:%@",
         aSession, @(canPrompt), @(objectType), urlString, @(allowURLSubs), environment, oldCWD,
         @(forceUseOldCWD), command, isUTF8Number, providedSubs, windowController);

    Profile *profile = [aSession profile];
    Profile *profileForComputingCommand;

    if (forceUseOldCWD) {
        profileForComputingCommand = [profile dictionaryBySettingObject:kProfilePreferenceInitialDirectoryCustomValue forKey:KEY_CUSTOM_DIRECTORY];
    } else {
        profileForComputingCommand = profile;
    }

    NSString *cmd = command ?: [ITAddressBookMgr bookmarkCommand:profileForComputingCommand
                                                   forObjectType:objectType];
    NSString *name = profile[KEY_NAME];

    // If the command or name have any $$VARS$$ not accounted for above, prompt the user for
    // substitutions.
    NSDictionary *substitutions;
    if (providedSubs) {
        substitutions = providedSubs;
    } else {
        substitutions = [self substitutionsForCommand:cmd
                                          sessionName:name
                                    baseSubstitutions:allowURLSubs ? [self substitutionsForURL:urlString] : @{}
                                            canPrompt:canPrompt
                                               window:windowController.window];
    }
    if (!substitutions) {
        if (completion) {
            [aSession didFinishInitialization:NO];
            completion(NO);
        }
        return NO;
    }
    cmd = [cmd stringByReplacingOccurrencesOfString:@"$$$$" withString:@"$$"];

    name = [name stringByPerformingSubstitutions:substitutions];
    NSString *pwd;
    if (forceUseOldCWD) {
        pwd = oldCWD;
        DLog(@"Using oldcwd (forced). pwd is %@", pwd);
    } else {
        pwd = [ITAddressBookMgr bookmarkWorkingDirectory:profile forObjectType:objectType];
        DLog(@"pwd for profile+object type is %@", pwd);
    }
    if ([pwd length] == 0) {
        if (oldCWD) {
            pwd = oldCWD;
            DLog(@"pwd was empty. Use oldCWD of %@", pwd);
        } else {
            pwd = NSHomeDirectory();
            DLog(@"pwd was empty. Use home directory of %@", pwd);
        }
    }
    environment = [environment ?: @{} dictionaryBySettingObject:pwd forKey:@"PWD"];
    BOOL isUTF8;
    if (isUTF8Number) {
        isUTF8 = isUTF8Number.boolValue;
    } else {
        isUTF8 = ([iTermProfilePreferences unsignedIntegerForKey:KEY_CHARACTER_ENCODING inProfile:profile] == NSUTF8StringEncoding);
    }

    void (^wrapper)(BOOL) = ^(BOOL ok) {
        [aSession didFinishInitialization:ok];
        if (completion) {
            completion(ok);
        }
    };
    void (^block)(NSString *) = ^(NSString *result) {
        [windowController setName:result ?: @"" forSession:aSession];
        [self finishAttachingOrLaunchingSession:aSession
                                            cmd:cmd
                                     completion:wrapper
                                    environment:environment
                                         isUTF8:isUTF8
                               serverConnection:serverConnection
                                  substitutions:substitutions
                               windowController:windowController];
    };
    if ([iTermAdvancedSettingsModel evaluateSwiftyStrings]) {
        [iTermScriptFunctionCall evaluateString:name
                                        timeout:[iTermAdvancedSettingsModel timeoutForStringEvaluation]
                                         source:aSession.functionCallSource
                                     completion:^(NSString *result, NSError *error, NSSet<NSString *> *missing) {
                                         block(result ?: @"");
                                     }];
    } else {
        block(name);
    }
    return YES;
}

- (NSDictionary *)substitutionsForURL:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    return @{ @"$$URL$$": urlString ?: @"",
              @"$$HOST$$": [url host] ?: @"",
              @"$$USER$$": [url user] ?: @"",
              @"$$PASSWORD$$": [url password] ?: @"",
              @"$$PORT$$": [url port] ? [[url port] stringValue] : @"",
              @"$$PATH$$": [url path] ?: @"",
              @"$$RES$$": [url resourceSpecifier] ?: @"" };
}

// Execute the given program and set the window title if it is uninitialized.
- (void)startProgram:(NSString *)command
         environment:(NSDictionary *)prog_env
              isUTF8:(BOOL)isUTF8
           inSession:(PTYSession*)theSession
        substitutions:(NSDictionary *)substitutions
    windowController:(PseudoTerminal *)term
          completion:(void (^ _Nullable)(BOOL))completion {
    [theSession startProgram:command
                 environment:prog_env
                      isUTF8:isUTF8
               substitutions:substitutions
                  completion:^(BOOL ok) {
                      [term setWindowTitle];
                      if (completion) {
                          completion(ok);
                      }
                  }];
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
    [_parameterPanelWindowController window];
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
