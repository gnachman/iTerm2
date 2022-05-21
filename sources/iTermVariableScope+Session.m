//
//  iTermVariableScope+Session.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/17/19.
//

#import "iTermVariableScope+Session.h"
#import "iTermVariableScope+Tab.h"
#import "iTermVariables.h"

@implementation iTermVariableScope (Session)

+ (instancetype)newSessionScopeWithVariables:(iTermVariables *)variables {
    iTermVariableScope *scope = [[self alloc] init];
    [scope addVariables:variables toScopeNamed:nil];
    [scope addVariables:[iTermVariables globalInstance] toScopeNamed:iTermVariableKeyGlobalScopeName];
    return scope;
}

- (NSString *)autoLogId {
    return [self valueForVariableName:iTermVariableKeySessionAutoLogID];
}

- (void)setAutoLogId:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionAutoLogID];
}

- (NSNumber *)columns {
    return [self valueForVariableName:iTermVariableKeySessionColumns];
}

- (void)setColumns:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionColumns];
}

- (NSString *)creationTimeString {
    return [self valueForVariableName:iTermVariableKeySessionCreationTimeString];
}

- (void)setCreationTimeString:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionCreationTimeString];
}

- (NSString *)hostname {
    return [self valueForVariableName:iTermVariableKeySessionHostname];
}

- (void)setHostname:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionHostname];
}

- (NSString *)ID {
    return [self valueForVariableName:iTermVariableKeySessionID];
}

- (void)setID:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionID];
}

- (NSString *)lastCommand {
    return [self valueForVariableName:iTermVariableKeySessionLastCommand];
}

- (void)setLastCommand:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionLastCommand];
}

- (NSString *)path {
    return [self valueForVariableName:iTermVariableKeySessionPath];
}

- (void)setPath:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionPath];
}

- (NSString *)name {
    return [self valueForVariableName:iTermVariableKeySessionName];
}

- (void)setName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionName];
}

- (NSNumber *)rows {
    return [self valueForVariableName:iTermVariableKeySessionRows];
}

- (void)setRows:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionRows];
}

- (NSString *)tty {
    return [self valueForVariableName:iTermVariableKeySessionTTY];
}

- (void)setTty:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTTY];
}

- (NSString *)username {
    return [self valueForVariableName:iTermVariableKeySessionUsername];
}

- (void)setUsername:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionUsername];
}

- (NSString *)termid {
    return [self valueForVariableName:iTermVariableKeySessionTermID];
}

- (void)setTermid:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTermID];
}

- (NSString *)profileName {
    return [self valueForVariableName:iTermVariableKeySessionProfileName];
}

- (void)setProfileName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionProfileName];
}

- (NSString *)terminalIconName {
    return [self valueForVariableName:iTermVariableKeySessionIconName];
}

- (void)setTerminalIconName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionIconName];
}

- (NSString *)triggerName {
    return [self valueForVariableName:iTermVariableKeySessionTriggerName];
}

- (void)setTriggerName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTriggerName];
}

- (NSString *)windowName {
    return [self valueForVariableName:iTermVariableKeySessionWindowName];
}

- (void)setWindowName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionWindowName];
}

- (NSString *)jobName {
    return [self valueForVariableName:iTermVariableKeySessionJob];
}

- (void)setJobName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionJob];
}

- (NSString *)processTitle {
    return [self valueForVariableName:iTermVariableKeySessionProcessTitle];
}

- (void)setProcessTitle:(NSString *)processTitle {
    [self setValue:processTitle forVariableNamed:iTermVariableKeySessionProcessTitle];
}

- (NSString *)commandLine {
    return [self valueForVariableName:iTermVariableKeySessionCommandLine];
}

- (void)setCommandLine:(NSString *)commandLine {
    [self setValue:commandLine forVariableNamed:iTermVariableKeySessionCommandLine];
}

- (NSString *)presentationName {
    return [self valueForVariableName:iTermVariableKeySessionPresentationName];
}

- (void)setPresentationName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionPresentationName];
}

- (NSString *)tmuxPaneTitle {
    return [self valueForVariableName:iTermVariableKeySessionTmuxPaneTitle];
}

- (void)setTmuxPaneTitle:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxPaneTitle];
}

- (NSString *)tmuxRole {
    return [self valueForVariableName:iTermVariableKeySessionTmuxRole];
}

- (void)setTmuxRole:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxRole];
}

- (NSString *)tmuxClientName {
    return [self valueForVariableName:iTermVariableKeySessionTmuxClientName];
}

- (void)setTmuxClientName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxClientName];
}

- (NSString *)autoNameFormat {
    return [self valueForVariableName:iTermVariableKeySessionAutoNameFormat];
}

- (void)setAutoNameFormat:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionAutoNameFormat];
}

- (NSString *)autoName {
    return [self valueForVariableName:iTermVariableKeySessionAutoName];
}

- (void)setAutoName:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionAutoName];
}

- (NSNumber *)tmuxWindowPane {
    return [self valueForVariableName:iTermVariableKeySessionTmuxWindowPane];
}

- (void)setTmuxWindowPane:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxWindowPane];
}

- (NSString *)tmuxWindowPaneIndex {
    return [self valueForVariableName:iTermVariableKeySessionTmuxWindowPaneIndex];
}

- (void)setTmuxWindowPaneIndex:(NSString *)tmuxWindowPaneIndex {
    [self setValue:tmuxWindowPaneIndex forVariableNamed:iTermVariableKeySessionTmuxWindowPaneIndex];
}

- (NSNumber *)jobPid {
    return [self valueForVariableName:iTermVariableKeySessionJobPid];
}

- (void)setJobPid:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionJobPid];
}

- (NSNumber *)pid {
    return [self valueForVariableName:iTermVariableKeySessionChildPid];
}

- (void)setPid:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionChildPid];
}

- (NSNumber *)effectiveRootPid {
    return [self valueForVariableName:iTermVariableKeySessionEffectiveSessionRootPid];
}

- (void)setEffectiveRootPid:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionEffectiveSessionRootPid];
}

- (NSString *)tmuxStatusLeft {
    return [self valueForVariableName:iTermVariableKeySessionTmuxStatusLeft];
}

- (void)setTmuxStatusLeft:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxStatusLeft];
}

- (NSString *)tmuxStatusRight {
    return [self valueForVariableName:iTermVariableKeySessionTmuxStatusRight];
}

- (void)setTmuxStatusRight:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionTmuxStatusRight];
}

- (NSNumber *)mouseReportingMode {
    return [self valueForVariableName:iTermVariableKeySessionMouseReportingMode];
}

- (void)setMouseReportingMode:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionMouseReportingMode];
}

- (NSString *)badge {
    return [self valueForVariableName:iTermVariableKeySessionBadge];
}

- (void)setBadge:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionBadge];
}

- (iTermVariableScope<iTermTabScope> *)tab {
    return [iTermVariableScope newTabScopeWithVariables:[self valueForVariableName:iTermVariableKeySessionTab]];
}

- (NSString *)selection {
    return [self valueForVariableName:iTermVariableKeySessionSelection];
}

- (void)setSelection:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionSelection];
}

- (NSNumber *)selectionLength {
    return [self valueForVariableName:iTermVariableKeySessionSelectionLength];
}

- (void)setSelectionLength:(NSNumber *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionSelectionLength];
}

- (NSNumber *)bellCount {
    return [self valueForVariableName:iTermVariableKeySessionBellCount];
}

- (void)setBellCount:(NSNumber *)bellCount {
    [self setValue:bellCount forVariableNamed:iTermVariableKeySessionBellCount];
}

- (NSNumber *)showingAlternateScreen {
    return [self valueForVariableName:iTermVariableKeySessionShowingAlternateScreen];
}

- (void)setShowingAlternateScreen:(NSNumber *)showingAlternateScreen {
    [self setValue:showingAlternateScreen forVariableNamed:iTermVariableKeySessionShowingAlternateScreen];
}

- (NSString *)logFilename {
    return [self valueForVariableName:iTermVariableKeySessionLogFilename];
}

- (void)setLogFilename:(NSString *)newValue {
    [self setValue:newValue forVariableNamed:iTermVariableKeySessionLogFilename];
}

- (NSArray *)mouseInfo {
    return [self valueForVariableName:iTermVariableKeySessionMouseInfo];
}

- (void)setMouseInfo:(NSArray *)mouseInfo {
    assert(mouseInfo.count == 7);
    assert([mouseInfo[0] isKindOfClass:[NSNumber class]]);  // x
    assert([mouseInfo[1] isKindOfClass:[NSNumber class]]);  // y
    assert([mouseInfo[2] isKindOfClass:[NSNumber class]]);  // button
    assert([mouseInfo[3] isKindOfClass:[NSNumber class]]);  // count
    assert([mouseInfo[4] isKindOfClass:[NSArray class]]);  // modifiers
    for (id obj in mouseInfo[4]) {
        assert([obj isKindOfClass:[NSNumber class]]);  // modifier
    }
    assert([mouseInfo[5] isKindOfClass:[NSNumber class]]);  // side effects
    assert([mouseInfo[6] isKindOfClass:[NSNumber class]]);  // state
    [self setValue:mouseInfo forVariableNamed:iTermVariableKeySessionMouseInfo];
}

- (BOOL)applicationKeypad {
    return [[self valueForVariableName:iTermVariableKeySessionApplicationKeypad] boolValue];
}

- (void)setApplicationKeypad:(BOOL)value {
    [self setValue:@(value) forVariableNamed:iTermVariableKeySessionApplicationKeypad];
}

@end
