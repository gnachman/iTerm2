#import "PTYSession+Scripting.h"

#import "DebugLogging.h"
#import "iTermProfilePreferences.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Session.h"
#import "NSColor+iTerm.h"
#import "NSObject+iTerm.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "PTYTab.h"
#import "WindowControllerInterface.h"

@implementation PTYSession (Scripting)

// Object specifier
- (NSScriptObjectSpecifier *)objectSpecifier {
    if (![self.delegate realParentWindow]) {
        // TODO(georgen): scripting is broken while in instant replay.
        return nil;
    }
    id classDescription = [NSClassDescription classDescriptionForClass:[PTYTab class]];

    return [[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription
                                                       containerSpecifier:[self.delegate objectSpecifier]
                                                                      key:@"sessions"
                                                                 uniqueID:self.guid];
}

// Handlers for supported commands:
- (void)handleExecScriptCommand:(NSScriptCommand *)aCommand {
    // if we are already doing something, get out.
    if ([self.shell pid] > 0) {
        DLog(@"Beep: Can't execute script because there's already a process");
        NSBeep();
        return;
    }

    // Get the command's arguments:
    NSDictionary *args = [aCommand evaluatedArguments];

    [aCommand suspendExecution];
    [self startProgram:args[@"command"]
                   ssh:NO
           environment:@{}
           customShell:nil
                isUTF8:[args[@"isUTF8"] boolValue]
         substitutions:nil
           arrangement:nil
            completion:^(BOOL ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [aCommand resumeExecutionWithResult:nil];
        });
    }];

    return;
}

- (void)handleSelectCommand:(NSScriptCommand *)command {
    [self.delegate setActiveSession:self];
}

- (void)handleClearScriptCommand:(NSScriptCommand *)command {
    [self clearBuffer];
}

- (void)handleWriteScriptCommand:(NSScriptCommand *)command {
    // Get the command's arguments:
    NSDictionary *args = [command evaluatedArguments];
    // optional argument follows (might be nil):
    NSString *contentsOfFile = [args objectForKey:@"contentsOfFile"];
    // optional argument follows (might be nil):
    NSString *text = [args objectForKey:@"text"];
    // optional argument follows (might be nil; if so, defaults to true):
    BOOL newline = ( [args objectForKey:@"newline"] ? [[args objectForKey:@"newline"] boolValue] : YES );
    NSString *aString = nil;

    if (text && contentsOfFile) {
        [command setScriptErrorNumber:1];
        [command setScriptErrorString:@"Only one of text or contents of file should be specified."];
        return;
    }
    if (!text && !contentsOfFile) {
        [command setScriptErrorNumber:2];
        [command setScriptErrorString:@"Neither text nor contents of file was specified."];
        return;
    }

    if (![text isKindOfClass:[NSString class]]) {
        text = [text description];
    }
    if (text != nil) {
        if (newline) {
            aString = [NSString stringWithFormat:@"%@\r", text];
        } else {
            aString = text;
        }
    }

    if (contentsOfFile != nil) {
        aString = [NSString stringWithContentsOfFile:contentsOfFile
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
    }

    if (self.tmuxMode == TMUX_CLIENT) {
        [self writeTask:aString];
    } else if (aString != nil && [self.shell pid] > 0) {
        int i = 0;
        // wait here until we have had some output
        while ([self.shell hasOutput] == NO && i < 1000000) {
            usleep(50000);
            i += 50000;
        }

        [self writeTask:aString];
    }
}

- (id)handleVariableNamedCommand:(NSScriptCommand *)command {
    NSDictionary *args = [command evaluatedArguments];
    NSString *name = args[@"name"];
    if (!name) {
        [command setScriptErrorNumber:1];
        [command setScriptErrorString:@"No name given"];
        return nil;
    }

    id value = [self.variablesScope valueForVariableName:name];
    if ([NSString castFrom:value]) {
        return value;
    } else if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    } else {
        return nil;
    }
}

- (id)handleSetVariableNamedCommand:(NSScriptCommand *)command {
    NSDictionary *args = [command evaluatedArguments];
    NSString *name = args[@"name"];
    NSString *value = args[@"value"];
    if (!name) {
        [command setScriptErrorNumber:1];
        [command setScriptErrorString:@"No name given"];
        return nil;
    }
    if (!value) {
        [command setScriptErrorNumber:2];
        [command setScriptErrorString:@"No value given"];
        return nil;
    }
    if (![name hasPrefix:@"user."]) {
        [command setScriptErrorNumber:3];
        [command setScriptErrorString:@"Only user variables may be set. Name must start with “user.”."];
        return nil;
    }
    [self.variablesScope setValue:value forVariableNamed:name];
    return value;
}

- (PTYSession *)activateSessionAndTab {
    PTYSession *saved = [self.delegate.realParentWindow currentSession];
    [self.delegate sessionSelectContainingTab];
    [self.delegate setActiveSession:self];
    return saved;
}

- (void)splitVertically:(BOOL)vertically
            withProfile:(Profile *)profile
                command:(NSString *)command
             completion:(void (^)(PTYSession *session))completion {
    PTYSession *formerSession = [self activateSessionAndTab];
    if (command) {
        // Create a modified profile to run "command".
        NSMutableDictionary *temp = [profile mutableCopy];
        temp[KEY_CUSTOM_COMMAND] = kProfilePreferenceCommandTypeCustomValue;
        temp[KEY_COMMAND_LINE] = command;
        profile = temp;
    }
    // NOTE: This will return nil for tmux tabs. I could fix it by using the async version of the
    // split function, but this is Applescript and I hate it.
    [[self.delegate realParentWindow] asyncSplitVertically:vertically
                                                    before:NO
                                                   profile:profile
                                             targetSession:[[self.delegate realParentWindow] currentSession]
                                                completion:nil
                                                     ready:^(PTYSession *session, BOOL ok) {
        [formerSession activateSessionAndTab];
        completion(session);
    }];
}

- (id)handleSplitVertically:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (profile) {
        PTYSession *formerSession = [self activateSessionAndTab];
        [scriptCommand suspendExecution];
        [self splitVertically:YES
                  withProfile:profile
                      command:args[@"command"]
                   completion:^(PTYSession *session) {
            [formerSession activateSessionAndTab];
            dispatch_async(dispatch_get_main_queue(), ^{
                [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
            });
        }];
        return nil;
    } else {
        [scriptCommand setScriptErrorNumber:1];
        [scriptCommand setScriptErrorString:[NSString stringWithFormat:@"No profile named %@",
                                             profileName]];
        return nil;
    }
}

- (id)handleSplitVerticallyWithDefaultProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    [scriptCommand suspendExecution];
    [self splitVertically:YES
              withProfile:[[ProfileModel sharedInstance] defaultBookmark]
                  command:args[@"command"]
               completion:^(PTYSession *session) {
        [formerSession activateSessionAndTab];
        dispatch_async(dispatch_get_main_queue(), ^{
            [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
        });
    }];
    return nil;
}

- (id)handleSplitVerticallyWithSameProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    [scriptCommand suspendExecution];
    [self splitVertically:YES
              withProfile:self.profile
                  command:args[@"command"]
               completion:^(PTYSession *session) {
        [formerSession activateSessionAndTab];
        dispatch_async(dispatch_get_main_queue(), ^{
            [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
        });
    }];
    return nil;
}

- (id)handleSplitHorizontally:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (profile) {
        PTYSession *formerSession = [self activateSessionAndTab];
        [scriptCommand suspendExecution];
        [self splitVertically:NO
                  withProfile:profile
                      command:args[@"command"]
                   completion:^(PTYSession *session) {
            [formerSession activateSessionAndTab];
            dispatch_async(dispatch_get_main_queue(), ^{
                [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
            });
        }];
        return nil;
    } else {
        [scriptCommand setScriptErrorNumber:1];
        [scriptCommand setScriptErrorString:[NSString stringWithFormat:@"No profile named %@",
                                             profileName]];
    }
    return nil;
}

- (id)handleSplitHorizontallyWithDefaultProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    [scriptCommand suspendExecution];
    [self splitVertically:NO
              withProfile:[[ProfileModel sharedInstance] defaultBookmark]
                  command:args[@"command"]
               completion:^(PTYSession *session) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
        });
        [formerSession activateSessionAndTab];
    }];
    return nil;
}

- (id)handleSplitHorizontallyWithSameProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    [scriptCommand suspendExecution];
    [self splitVertically:NO
              withProfile:self.profile
                  command:args[@"command"]
               completion:^(PTYSession *session) {
        [formerSession activateSessionAndTab];
        dispatch_async(dispatch_get_main_queue(), ^{
            [scriptCommand resumeExecutionWithResult:session.objectSpecifier ? session : nil];
        });
    }];
    return nil;
}

- (void)handleTerminateScriptCommand:(NSScriptCommand *)command {
    [self.delegate closeSession:self];
}

- (void)handleCloseCommand:(NSScriptCommand *)scriptCommand {
    [self.delegate.realParentWindow closeSessionWithConfirmation:self];
}

- (NSColor *)backgroundColor {
    return [self.screen.colorMap colorForKey:kColorMapBackground];
}

- (void)setBackgroundColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_BACKGROUND_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)boldColor {
    return [self.screen.colorMap colorForKey:kColorMapBold];
}

- (void)setBoldColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_BOLD_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)cursorColor {
    return [self.screen.colorMap colorForKey:kColorMapCursor];
}

- (void)setCursorColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_CURSOR_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)cursorTextColor {
    return [self.screen.colorMap colorForKey:kColorMapCursorText];
}

- (void)setCursorTextColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_CURSOR_TEXT_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)foregroundColor {
    return [self.screen.colorMap colorForKey:kColorMapForeground];
}

- (void)setForegroundColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_FOREGROUND_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)underlineColor {
    return [self.screen.colorMap colorForKey:kColorMapUnderline];
}

- (void)setUnderlineColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_UNDERLINE_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)selectedTextColor {
    return [self.screen.colorMap colorForKey:kColorMapSelectedText];
}

- (void)setSelectedTextColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_SELECTED_TEXT_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)selectionColor {
    return [self.screen.colorMap colorForKey:kColorMapSelection];
}

- (void)setSelectionColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_SELECTION_COLOR]: [color dictionaryValue] }];
}

- (NSString *)text {
    return [self.textview content];
}

- (NSString *)answerBackString {
    return [iTermProfilePreferences stringForKey:KEY_ANSWERBACK_STRING inProfile:self.profile];
}

- (void)setAnswerBackString:(NSString *)string {
    [self setSessionSpecificProfileValues:@{ KEY_ANSWERBACK_STRING: string ?: @"" }];
}

- (void)setName:(NSString *)name {
    [self setSessionSpecificProfileValues:@{ KEY_NAME: name ?: @"" }];
}

#pragma mark ANSI Colors

- (NSColor *)ansiBlackColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBlack];
}

- (void)setAnsiBlackColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_0_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiRedColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiRed];
}

- (void)setAnsiRedColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_1_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiGreenColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiGreen];
}

- (void)setAnsiGreenColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_2_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiYellowColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiYellow];
}

- (void)setAnsiYellowColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_3_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBlueColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBlue];
}

- (void)setAnsiBlueColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_4_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiMagentaColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiMagenta];
}

- (void)setAnsiMagentaColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_5_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiCyanColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiCyan];
}

- (void)setAnsiCyanColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_6_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiWhiteColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiWhite];
}

- (void)setAnsiWhiteColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_7_COLOR]: [color dictionaryValue] }];
}

#pragma mark Ansi Bright Colors

- (NSColor *)ansiBrightBlackColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiBlack];
}

- (void)setAnsiBrightBlackColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_8_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightRedColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiRed];
}

- (void)setAnsiBrightRedColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_9_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightGreenColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiGreen];
}

- (void)setAnsiBrightGreenColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_10_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightYellowColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiYellow];
}

- (void)setAnsiBrightYellowColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_11_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightBlueColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiBlue];
}

- (void)setAnsiBrightBlueColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_12_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightMagentaColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiMagenta];
}

- (void)setAnsiBrightMagentaColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_13_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightCyanColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiCyan];
}

- (void)setAnsiBrightCyanColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_14_COLOR]: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightWhiteColor {
    return [self.screen.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiWhite];
}

- (void)setAnsiBrightWhiteColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ [self amendedColorKey:KEY_ANSI_15_COLOR]: [color dictionaryValue] }];
}

- (void)setColumns:(int)columns {
    [[self.delegate realParentWindow] sessionInitiatedResize:self
                                                       width:columns
                                                      height:self.rows];
}

- (void)setRows:(int)rows {
    [[self.delegate realParentWindow] sessionInitiatedResize:self
                                                       width:self.columns
                                                      height:rows];
}

- (NSString *)profileNameForScripting {
  return self.profile[KEY_NAME];
}

- (NSString *)colorPresetName {
    return [ProfilesColorsPreferencesViewController nameOfPresetUsedByProfile:self.profile];
}

- (void)setColorPresetName:(NSString *)colorPresetName {
    [self setColorsFromPresetNamed:colorPresetName];
}

@end
