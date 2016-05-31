#import "PTYSession+Scripting.h"
#import "NSColor+iTerm.h"
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

    return [[[NSUniqueIDSpecifier alloc] initWithContainerClassDescription:classDescription
                                                        containerSpecifier:[self.delegate objectSpecifier]
                                                                       key:@"sessions"
                                                                  uniqueID:self.guid] autorelease];
}

// Handlers for supported commands:
- (void)handleExecScriptCommand:(NSScriptCommand *)aCommand {
    // if we are already doing something, get out.
    if ([self.shell pid] > 0) {
        NSBeep();
        return;
    }

    // Get the command's arguments:
    NSDictionary *args = [aCommand evaluatedArguments];

    [self startProgram:args[@"command"]
           environment:@{}
                isUTF8:[args[@"isUTF8"] boolValue]
         substitutions:nil];

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
    }
    
    return self.variables[name];
}

- (id)handleSetVariableNamedCommand:(NSScriptCommand *)command {
    NSDictionary *args = [command evaluatedArguments];
    NSString *name = args[@"name"];
    NSString *value = args[@"value"];
    if (!name) {
        [command setScriptErrorNumber:1];
        [command setScriptErrorString:@"No name given"];
    }
    if (!value) {
        [command setScriptErrorNumber:2];
        [command setScriptErrorString:@"No value given"];
    }
    if (![name hasPrefix:@"user."]) {
        [command setScriptErrorNumber:3];
        [command setScriptErrorString:@"Only user variables may be set. Name must start with “user.”."];
    }
    self.variables[[@"user." stringByAppendingString:name]] = value;
    [self.textview setBadgeLabel:[self badgeLabel]];
    return value;
}

- (PTYSession *)activateSessionAndTab {
    PTYSession *saved = [self.delegate.realParentWindow currentSession];
    [self.delegate sessionSelectContainingTab];
    [self.delegate setActiveSession:self];
    return saved;
}

- (PTYSession *)splitVertically:(BOOL)vertically
                    withProfile:(Profile *)profile
                        command:(NSString *)command {
    PTYSession *formerSession = [self activateSessionAndTab];
    if (command) {
        // Create a modified profile to run "command".
        NSMutableDictionary *temp = [[profile mutableCopy] autorelease];
        temp[KEY_CUSTOM_COMMAND] = @"Yes";
        temp[KEY_COMMAND_LINE] = command;
        profile = temp;
    }
    PTYSession *session = [[self.delegate realParentWindow] splitVertically:vertically
                                                                withProfile:profile];
    [formerSession activateSessionAndTab];
    return session;
}

- (id)handleSplitVertically:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (profile) {
        PTYSession *formerSession = [self activateSessionAndTab];
        PTYSession *session = [self splitVertically:YES
                                        withProfile:profile
                                            command:args[@"command"]];
        [formerSession activateSessionAndTab];
        return session;
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
    PTYSession *session = [self splitVertically:YES
                                    withProfile:[[ProfileModel sharedInstance] defaultBookmark]
                                        command:args[@"command"]];
    [formerSession activateSessionAndTab];
    return session;
}

- (id)handleSplitVerticallyWithSameProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    PTYSession *session = [self splitVertically:YES
                                    withProfile:self.profile
                                        command:args[@"command"]];
    [formerSession activateSessionAndTab];
    return session;
}

- (id)handleSplitHorizontally:(NSScriptCommand *)scriptCommand {
    NSDictionary *args = [scriptCommand evaluatedArguments];
    NSString *profileName = args[@"profile"];
    Profile *profile = [[ProfileModel sharedInstance] bookmarkWithName:profileName];
    if (profile) {
        PTYSession *formerSession = [self activateSessionAndTab];
        PTYSession *session = [self splitVertically:NO
                                        withProfile:profile
                                            command:args[@"command"]];
        [formerSession activateSessionAndTab];
        return session;
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
    PTYSession *session = [self splitVertically:NO
                                    withProfile:[[ProfileModel sharedInstance] defaultBookmark]
                                        command:args[@"command"]];
    [formerSession activateSessionAndTab];
    return session;
}

- (id)handleSplitHorizontallyWithSameProfile:(NSScriptCommand *)scriptCommand {
    PTYSession *formerSession = [self activateSessionAndTab];
    NSDictionary *args = [scriptCommand evaluatedArguments];
    PTYSession *session = [self splitVertically:NO
                                    withProfile:self.profile
                                        command:args[@"command"]];
    [formerSession activateSessionAndTab];
    return session;
}

- (void)handleTerminateScriptCommand:(NSScriptCommand *)command {
    [self.delegate closeSession:self];
}

- (void)handleCloseCommand:(NSScriptCommand *)scriptCommand {
    [self.delegate.realParentWindow closeSessionWithConfirmation:self];
}

- (NSColor *)backgroundColor {
    return [self.colorMap colorForKey:kColorMapBackground];
}

- (void)setBackgroundColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_BACKGROUND_COLOR: [color dictionaryValue] }];
}

- (NSColor *)boldColor {
    return [self.colorMap colorForKey:kColorMapBold];
}

- (void)setBoldColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_BOLD_COLOR: [color dictionaryValue] }];
}

- (NSColor *)cursorColor {
    return [self.colorMap colorForKey:kColorMapCursor];
}

- (void)setCursorColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_CURSOR_COLOR: [color dictionaryValue] }];
}

- (NSColor *)cursorTextColor {
    return [self.colorMap colorForKey:kColorMapCursorText];
}

- (void)setCursorTextColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_CURSOR_TEXT_COLOR: [color dictionaryValue] }];
}

- (NSColor *)foregroundColor {
    return [self.colorMap colorForKey:kColorMapForeground];
}

- (void)setForegroundColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_FOREGROUND_COLOR: [color dictionaryValue] }];
}

- (NSColor *)selectedTextColor {
    return [self.colorMap colorForKey:kColorMapSelectedText];
}

- (void)setSelectedTextColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_SELECTED_TEXT_COLOR: [color dictionaryValue] }];
}

- (NSColor *)selectionColor {
    return [self.colorMap colorForKey:kColorMapSelection];
}

- (void)setSelectionColor:(NSColor *)color {
    [self setSessionSpecificProfileValues:@{ KEY_SELECTION_COLOR: [color dictionaryValue] }];
}

- (NSString *)contents {
    return [self.textview content];
}

- (NSString *)answerBackString {
    return self.terminal.answerBackString;
}

- (void)setAnswerBackString:(NSString *)string {
    [self setSessionSpecificProfileValues:@{ KEY_ANSWERBACK_STRING: string ?: @"" }];
}

#pragma mark ANSI Colors

- (NSColor *)ansiBlackColor {
    return [self.colorMap colorForKey:kColorMapAnsiBlack];
}

- (void)setAnsiBlackColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_0_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiRedColor {
    return [self.colorMap colorForKey:kColorMapAnsiRed];
}

- (void)setAnsiRedColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_1_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiGreenColor {
    return [self.colorMap colorForKey:kColorMapAnsiGreen];
}

- (void)setAnsiGreenColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_2_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiYellowColor {
    return [self.colorMap colorForKey:kColorMapAnsiYellow];
}

- (void)setAnsiYellowColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_3_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBlueColor {
    return [self.colorMap colorForKey:kColorMapAnsiBlue];
}

- (void)setAnsiBlueColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_4_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiMagentaColor {
    return [self.colorMap colorForKey:kColorMapAnsiMagenta];
}

- (void)setAnsiMagentaColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_5_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiCyanColor {
    return [self.colorMap colorForKey:kColorMapAnsiCyan];
}

- (void)setAnsiCyanColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_6_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiWhiteColor {
    return [self.colorMap colorForKey:kColorMapAnsiWhite];
}

- (void)setAnsiWhiteColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_7_COLOR: [color dictionaryValue] }];
}

#pragma mark Ansi Bright Colors

- (NSColor *)ansiBrightBlackColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiBlack];
}

- (void)setAnsiBrightBlackColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_8_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightRedColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiRed];
}

- (void)setAnsiBrightRedColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_9_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightGreenColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiGreen];
}

- (void)setAnsiBrightGreenColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_10_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightYellowColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiYellow];
}

- (void)setAnsiBrightYellowColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_11_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightBlueColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiBlue];
}

- (void)setAnsiBrightBlueColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_12_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightMagentaColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiMagenta];
}

- (void)setAnsiBrightMagentaColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_13_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightCyanColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiCyan];
}

- (void)setAnsiBrightCyanColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_14_COLOR: [color dictionaryValue] }];
}

- (NSColor *)ansiBrightWhiteColor {
    return [self.colorMap colorForKey:kColorMapAnsiBrightModifier + kColorMapAnsiWhite];
}

- (void)setAnsiBrightWhiteColor:(NSColor*)color {
    [self setSessionSpecificProfileValues:@{ KEY_ANSI_15_COLOR: [color dictionaryValue] }];
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

- (NSString *)profileName {
  return self.profile[KEY_NAME];
}

@end
