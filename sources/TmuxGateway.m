//
//  TmuxGateway.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxGateway.h"

#import "iTerm2SharedARC-Swift.h"
#import "iTermApplicationDelegate.h"
#import "iTermAdvancedSettingsModel.h"
#import "TmuxController.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "VT100Token.h"

NSString * const kTmuxGatewayErrorDomain = @"kTmuxGatewayErrorDomain";;

#ifdef NEWLINE
#undef NEWLINE
#endif
#define NEWLINE @"\r"

//#define TMUX_VERBOSE_LOGGING
#ifdef TMUX_VERBOSE_LOGGING
#define TmuxLog NSLog
#else
#define TmuxLog DLog
#endif

static NSString *kCommandTarget = @"target";
static NSString *kCommandSelector = @"sel";
static NSString *kCommandString = @"string";
static NSString *kCommandObject = @"object";
static NSString *kCommandIsInitial = @"isInitial";
static NSString *kCommandFlags = @"flags";
static NSString *kCommandId = @"id";
static NSString *kCommandIsInList = @"inList";
static NSString *kCommandIsLastInList = @"lastInList";
static NSString *kCommandTimestamp = @"timestamp";

@interface iTermTmuxSubscriptionHandle()
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) void (^block)(NSString *, NSArray<NSString *> *);
@property (nonatomic) BOOL initialized;

- (instancetype)initWithBlock:(void (^)(NSString *, NSArray<NSString *> *))block NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setValue:(NSString *)value arguments:(NSArray<NSString *> *)args;
@end

@implementation iTermTmuxSubscriptionHandle

- (instancetype)initWithBlock:(void (^)(NSString *, NSArray<NSString *> *))block {
    self = [super init];
    if (self) {
        static NSInteger next = 1;
        _identifier = [[NSString stringWithFormat:@"it2_%@", @(next++)] retain];
        _block = [block copy];
    }
    return self;
}

- (void)dealloc {
    [_identifier release];
    [_block release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p id=%@>", NSStringFromClass(self.class), self, _identifier];
}

- (void)setValue:(NSString *)value arguments:(NSArray<NSString *> *)args {
    self.block(value, args);
}

- (void)setValid {
    _isValid = YES;
}

@end

@implementation TmuxGateway {
    // Set to YES when the remote host closed the connection. We won't send commands when this is
    // set.
    BOOL disconnected_;

    // Data from parsing an incoming command
    ControlCommand command_;

    NSMutableArray *commandQueue_;  // NSMutableDictionary objects
    NSMutableString *currentCommandResponse_;
    NSMutableDictionary *currentCommand_;  // Set between %begin and %end
    NSMutableData *currentCommandData_;

    BOOL acceptNotifications_;  // Initially NO. When YES, respond to notifications.
    NSMutableString *strayMessages_;

    // When we get the first %begin-%{end,error} we notify the delegate. Until that happens, this is
    // set to NO.
    BOOL _initialized;
    NSMutableDictionary<NSString *, iTermTmuxSubscriptionHandle *> *_subscriptions;
    int _sessionID;  // -1 if uninitialized
}

@synthesize delegate = delegate_;
@synthesize acceptNotifications = acceptNotifications_;
@synthesize detachSent = detachSent_;

- (instancetype)initWithDelegate:(id<TmuxGatewayDelegate>)delegate dcsID:(NSString *)dcsID {
    self = [super init];
    if (self) {
        delegate_ = delegate;
        commandQueue_ = [[NSMutableArray alloc] init];
        strayMessages_ = [[NSMutableString alloc] init];
        _subscriptions = [[NSMutableDictionary alloc] init];
        _dcsID = [dcsID copy];
        _sessionID = -1;
    }
    return self;
}

- (void)dealloc {
    [commandQueue_ release];
    [currentCommand_ release];
    [currentCommandResponse_ release];
    [currentCommandData_ release];
    [strayMessages_ release];
    [_minimumServerVersion release];
    [_maximumServerVersion release];
    [_dcsID release];
    [_subscriptions release];

    [super dealloc];
}

- (void)abortWithErrorMessage:(NSString *)message {
    [self abortWithErrorMessage:[NSString stringWithFormat:@"%@", message]
                          title:@"tmux Reported a Problem"];
}

// TODO: be more forgiving of errors.
- (void)abortWithErrorMessage:(NSString *)message title:(NSString *)title {
    // This can run in a side-effect and it's not safe to start a runloop in a side effect.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        alert.messageText = title;
        alert.informativeText = message;
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    });
    [self detach];
    [delegate_ tmuxHostDisconnected:[[_dcsID copy] autorelease]];  // Force the client to quit
}

- (void)doubleAttachDetectedForSessionGUID:(NSString *)sessionGuid {
    [self.delegate tmuxDoubleAttachForSessionGUID:sessionGuid];
}

- (NSData *)decodeEscapedOutput:(const char *)bytes
{
    NSMutableData *data = [NSMutableData data];
    unsigned char c;
    for (int i = 0; bytes[i]; i++) {
        c = bytes[i];
        if (c < ' ') {
            continue;
        }
        if (c == '\\') {
            // Read exactly three bytes of octal values, or else set c to '?'.
            c = 0;
            for (int j = 0; j < 3; j++) {
                i++;
                if (bytes[i] == '\r') {
                    // Ignore \r's that the line driver sprinkles in at its pleasure.
                    continue;
                }
                if (bytes[i] < '0' || bytes[i] > '7') {
                    c = '?';
                    i--;  // Back up in case bytes[i] is a null; we don't want to go off the end.
                    break;
                }
                c *= 8;
                c += bytes[i] - '0';
            }
        }
        [data appendBytes:&c length:1];
    }
    return data;
}

// %extended-output %<pane id> <latency> [more args?] : <data...><newline>
- (void)parseExtendedOutputCommandData:(NSData *)input {
    // Null terminate so we can do some string parsing without too much pain.
    NSMutableData *data = [NSMutableData dataWithData:input];
    [data appendBytes:"" length:1];

    // This one is tricky to parse because the string version of the command could have bogus UTF-8.
    // 3.1 and earlier:
    //   %output %<pane id> <data...><newline>
    // 3.2 and later, when pause mode is enabled:
    //   %output %<pane id> <latency> <data...><newline>
    const char *command = [data bytes];
    char *space = strchr(command, ' ');
    if (!space) {
        goto error;
    }
    const char *outputCommand = "%extended-output";
    if (strncmp(outputCommand, command, strlen(outputCommand))) {
        goto error;
    }

    // Pane ID
    const char *paneId = space + 1;
    if (*paneId != '%') {
        goto error;
    }
    paneId++;
    space = strchr(paneId, ' ');
    if (!space) {
        goto error;
    }
    char *endptr = NULL;
    int windowPane = strtol(paneId, &endptr, 10);
    if (windowPane < 0 || endptr != space) {
        goto error;
    }

    // Latency
    const char *latency = space + 1;
    space = strchr(latency, ' ');
    if (!space) {
        goto error;
    }
    endptr = NULL;
    NSNumber *ms = @(strtoll(latency, &endptr, 10));
    ms = @(ms.doubleValue / 1000.0);
    if (endptr != space) {
        goto error;
    }

    // Skip unknown params
    const char *colon = strchr(space + 1, ':');
    if (!colon) {
        goto error;
    }
    if (colon[1] != ' ') {
        goto error;
    }

    const char *encodedData = colon + 2;

    // Payload
    NSData *decodedData = [self decodeEscapedOutput:encodedData];

    TmuxLog(@"Run tmux command: \"%%extended-output \"%%%d\" %@ %.*s",
            windowPane, ms, (int)[decodedData length], (const char *)[decodedData bytes]);

    [delegate_ tmuxReadTask:decodedData windowPane:windowPane latency:ms];

    return;
error:
    [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%num data): \"%s\"", command]];
}

// %output %<pane id> <data...><newline>
- (void)parseOutputCommandData:(NSData *)input {
    // Null terminate so we can do some string parsing without too much pain.
    NSMutableData *data = [NSMutableData dataWithData:input];
    [data appendBytes:"" length:1];

    // This one is tricky to parse because the string version of the command could have bogus UTF-8.
    const char *command = [data bytes];
    char *space = strchr(command, ' ');
    if (!space) {
        goto error;
    }
    const char *outputCommand = "%output";
    if (strncmp(outputCommand, command, strlen(outputCommand))) {
        goto error;
    }

    // Pane ID
    const char *paneId = space + 1;
    if (*paneId != '%') {
        goto error;
    }
    paneId++;
    space = strchr(paneId, ' ');
    if (!space) {
        goto error;
    }
    char *endptr = NULL;
    int windowPane = strtol(paneId, &endptr, 10);
    if (windowPane < 0 || endptr != space) {
        goto error;
    }

    // Payload
    NSData *decodedData = [self decodeEscapedOutput:space + 1];

    TmuxLog(@"Run tmux command: \"%%output \"%%%d\" %.*s",
            windowPane, (int)[decodedData length], (const char *)[decodedData bytes]);

    [delegate_ tmuxReadTask:decodedData windowPane:windowPane latency:nil];

    return;
error:
    [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%num data): \"%s\"", command]];
}

- (NSNumber *)layoutIsZoomed:(NSString *)args {
    // window-layout window-visible-layout window-flags
    NSArray<NSString *> *components = [args componentsSeparatedByString:@" "];
    if (components.count < 3) {
        return nil;
    }
    NSString *windowFlags = components[2];
    return @([windowFlags containsString:@"Z"]);
}

- (void)parseLayoutChangeCommand:(NSString *)command
{
    // %layout-change <window> <layout>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%layout-change @([0-9]+) (.*)"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%layout-change <window> <layout>): \"%@\"",
                                     command]];
        return;
    }
    int window = [[components objectAtIndex:1] intValue];
    NSString *layout = [components objectAtIndex:2];
    [delegate_ tmuxUpdateLayoutForWindow:window
                                  layout:layout
                                  zoomed:[self layoutIsZoomed:layout]
                                    only:YES];
}

- (void)broadcastWindowChange
{
    [delegate_ tmuxWindowsDidChange];
}

- (void)parseWindowAddCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-add @([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-add id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowAddedWithId:[[components objectAtIndex:1] intValue]];
}

- (void)parseWindowCloseCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%(?:unlinked-)?window-close @([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-close id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowClosedWithId:[[components objectAtIndex:1] intValue]];
}

- (void)parseWindowRenamedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%(?:unlinked-)?window-renamed @([0-9]+) (.*)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-renamed id new_name): \"%@\"", command]];
        return;
    }
    NSString *escaped = components[2];
    NSString *name = [escaped it_unescapedTmuxWindowName];
    [delegate_ tmuxWindowRenamedWithId:[[components objectAtIndex:1] intValue]
                                    to:name];
}

- (void)parseSessionRenamedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-renamed \\$([0-9]+) (.+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-renamed id name): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSession:[[components objectAtIndex:1] intValue] renamed:[components objectAtIndex:2]];
}

- (void)parseSessionChangeCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-changed \\$([0-9]+) (.+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-changed id name): \"%@\"", command]];
        return;
    }
    _sessionID = [[components objectAtIndex:1] intValue];
    [delegate_ tmuxSessionChanged:[components objectAtIndex:2] sessionId:[[components objectAtIndex:1] intValue]];
}

- (void)parseSessionsChangedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%sessions-changed$"];
    if (components.count != 1) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%sessions-changed): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSessionsChanged];
}

- (void)parseWindowPaneChangedCommand:(NSString *)command {
    NSArray<NSString *> *components = [command captureComponentsMatchedByRegex:@"^%window-pane-changed @([0-9]+) %([0-9]+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-pane-changed @window-id %%pane-id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxActiveWindowPaneDidChangeInWindow:[components[1] intValue] toWindowPane:[components[2] intValue]];
}

// %session-window-changed $0 @0
- (void)parseSessionWindowChangedCommand:(NSString *)command {
    NSArray<NSString *> *components = [command captureComponentsMatchedByRegex:@"^%session-window-changed \\$([0-9]+) @([0-9]+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-window-changed $session-id @window-id): \"%@\"", command]];
        return;
    }
    const int sid = [components[1] intValue];
    if (sid != _sessionID) {
        return;
    }
    [delegate_ tmuxSessionWindowDidChangeTo:[components[2] intValue]];
}

- (void)parsePauseCommand:(NSString *)command {
    NSArray<NSString *> *components = [command captureComponentsMatchedByRegex:@"^%pause %([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%pause %%wp): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowPaneDidPause:components[1].intValue
                         notification:YES];
}

// %subscription-changed name $a @b x %c : value
// Where a = session, b = window, x = index, c = pane and any can be - if they are not appropriate
// to that subscription (so a session subscription will not include b,x,c and a window not
// include c.
- (void)parseSubscriptionChangedCommand:(NSString *)command {
    NSArray<NSString *> *components = [command captureComponentsMatchedByRegex:@"^%subscription-changed ([^:]+) : (.*)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%subscription-changed sid [...] : value): \"%@\"", command]];
        return;
    }
    NSString *args = components[1];
    NSString *value = components[2];
    NSArray<NSString *> *parts = [args componentsSeparatedByString:@" "];
    NSString *sid = parts.firstObject ?: @"";
    [_subscriptions[sid] setValue:value arguments:parts];
}

- (void)forceDetach {
    [self hostDisconnected];
}

- (void)hostDisconnected {
    disconnected_ = YES;
    [delegate_ tmuxHostDisconnected:[[_dcsID copy] autorelease]];
    [commandQueue_ removeAllObjects];
}

// Accessors for objects in the current-command dictionary.
- (id)objectConvertingNullInDictionary:(NSDictionary *)dict forKey:(id)key {
    id object = [dict objectForKey:key];
    if ([object isKindOfClass:[NSNull class]]) {
        return nil;
    } else {
        return object;
    }
}

- (id)currentCommandTarget {
    return [self objectConvertingNullInDictionary:currentCommand_
                                           forKey:kCommandTarget];
}

- (SEL)currentCommandSelector {
    NSString *theString = [self objectConvertingNullInDictionary:currentCommand_
                                                          forKey:kCommandSelector];
    if (theString) {
        return NSSelectorFromString(theString);
    } else {
        return nil;
    }
}

- (id)currentCommandObject {
    return [self objectConvertingNullInDictionary:currentCommand_
                                           forKey:kCommandObject];
}

- (int)currentCommandFlags {
    return [[self objectConvertingNullInDictionary:currentCommand_
                                            forKey:kCommandFlags] intValue];
}

- (BOOL)commandIsTmux21Quirk {
    return ([currentCommandResponse_ hasPrefix:@"bad working directory:"] &&
            [currentCommand_[kCommandString] hasPrefix:@"new-window"] &&
            [currentCommand_[kCommandString] containsString:@"-c"] &&
            [self.maximumServerVersion compare:@2.1] != NSOrderedAscending);
}

- (void)abortWithErrorForCurrentCommand {
    if ([self commandIsTmux21Quirk]) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Error: %@.\n\nTmux 2.1 and earlier will refuse to create a new window pane with a nonexistent initial working directory.\n\nInfo:\n%@",
                                     currentCommandResponse_, currentCommand_]];
    } else {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Error: %@.\n\nInfo:\n%@", currentCommandResponse_, currentCommand_]];
    }
}

- (void)invokeCurrentCallbackWithError:(BOOL)withError {
    id target = [self currentCommandTarget];
    if (!target) {
        return;
    }
    SEL selector = [self currentCommandSelector];
    id obj = [self currentCommandObject];
    if (withError) {
        [target performSelector:selector
                     withObject:nil
                     withObject:obj];
        return;
    }
    if (_tmuxLogging) {
        [delegate_ tmuxPrintLine:[NSString stringWithFormat:@"[Normal response to “%@”]", currentCommand_[kCommandString]]];
    }
    if ([self currentCommandFlags] & kTmuxGatewayCommandWantsData) {
        [target performSelector:selector
                     withObject:currentCommandData_
                     withObject:obj];
    } else {
        [target performSelector:selector
                     withObject:currentCommandResponse_
                     withObject:obj];
    }
}

- (BOOL)shouldAutofailSubsequentCommands {
    if (![currentCommand_[kCommandIsInList] boolValue]) {
        return NO;
    }
    if ([currentCommand_[kCommandIsLastInList] boolValue]) {
        return NO;
    }
    // Remove subsequent commands belonging to the same list so we can go back to life
    // as usual.
    DLog(@"Automatically fail the next command.");
    return YES;
}

- (void)performInitializationOnCommandResponseWithError:(BOOL)withError {
    if ([currentCommand_[kCommandIsInitial] boolValue]) {
        DLog(@"Begin accepting notifications");
        acceptNotifications_ = YES;
    }
    if (_initialized) {
        return;
    }
    _initialized = YES;
    const BOOL shouldTolerateError = !!([self currentCommandFlags] & kTmuxGatewayCommandShouldTolerateErrors);
    if (withError && !shouldTolerateError) {
        [delegate_ tmuxInitialCommandDidFailWithError:currentCommandResponse_];
    } else {
        [delegate_ tmuxInitialCommandDidCompleteSuccessfully];
    }
}

- (void)currentCommandResponseFinishedWithError:(BOOL)withError {
    while (YES) {
        if (withError) {
            if (_tmuxLogging) {
                [delegate_ tmuxPrintLine:[NSString stringWithFormat:@"[Error “%@” in response to “%@”]",
                                          currentCommandResponse_, currentCommand_[kCommandString]]];
            }
            const BOOL shouldTolerateError = ([self currentCommandFlags] & kTmuxGatewayCommandShouldTolerateErrors);
            if (!shouldTolerateError && (_initialized || currentCommand_[kCommandString])) {
                [self abortWithErrorForCurrentCommand];
                return;
            }
        }
        [self invokeCurrentCallbackWithError:withError];
        const BOOL failNext = withError && [self shouldAutofailSubsequentCommands];
        [self performInitializationOnCommandResponseWithError:withError];
        [self resetCurrentCommand];

        if (!failNext) {
            return;
        }
        [self beginHandlingNextResponseWithID:@"n/a"];
    };
}

- (void)parseBegin:(NSString *)command {
    if (currentCommand_) {
        [self abortWithErrorMessage:@"%begin without %end"];
        return;
    }
    int flags = -1;
    // begin commandId commandNumber[ flags]
    // flags = 0: Server-originated command
    // flags & 1: Client-originated command (default)
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%begin ([0-9]+) [0-9]+( [0-9]+)?$"];
    if (components.count < 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%begin command_id [flags]): \"%@\"", command]];
        return;
    }

    NSString *flagStr = [[components objectAtIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([flagStr length] > 0) {
        flags = [flagStr intValue];
    }
    if (!(flags & 1)) {
        // Not a client-originated command.
        TmuxLog(@"Begin auto response");
        currentCommand_ = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                               [components objectAtIndex:1], kCommandId,
                               nil] retain];
        [currentCommandResponse_ release];
        [currentCommandData_ release];
        currentCommandResponse_ = [[NSMutableString alloc] init];
        currentCommandData_ = [[NSMutableData alloc] init];
    } else {
        if (!commandQueue_.count) {
            [self abortWithErrorMessage:@"%begin with empty command queue"];
            return;
        }
        [self beginHandlingNextResponseWithID:components[1]];
        if (_tmuxLogging) {
            TmuxLog(@"Begin response to %@", [currentCommand_ objectForKey:kCommandString]);
            [delegate_ tmuxPrintLine:[NSString stringWithFormat:@"[Begin response for %@]", currentCommand_[kCommandString]]];
        }
    }
}

- (void)resetCurrentCommand {
    [currentCommand_ release];
    currentCommand_ = nil;
    [currentCommandResponse_ release];
    currentCommandResponse_ = nil;
    [currentCommandData_ release];
    currentCommandData_ = nil;
}

- (void)beginHandlingNextResponseWithID:(NSString *)commandId {
    assert(!currentCommand_);
    currentCommand_ = [commandQueue_[0] retain];
    currentCommand_[kCommandId] = commandId;

    [currentCommandResponse_ release];
    [currentCommandData_ release];
    currentCommandResponse_ = [[NSMutableString alloc] init];
    currentCommandData_ = [[NSMutableData alloc] init];
    [commandQueue_ removeObjectAtIndex:0];
}

- (void)stripLastNewline {
    if ([currentCommandResponse_ hasSuffix:@"\n"]) {
        // Strip the last newline.
        NSRange theRange = NSMakeRange(currentCommandResponse_.length - 1, 1);
        [currentCommandResponse_ replaceCharactersInRange:theRange
                                               withString:@""];
        [currentCommandData_ setLength:currentCommandData_.length - 1];
    }
}

- (BOOL)versionAtLeastDecimalNumberWithString:(NSString *)string {
    NSDecimalNumber *version = [NSDecimalNumber decimalNumberWithString:string];
    if (self.minimumServerVersion == nil) {
        return NO;
    }
    return ([self.minimumServerVersion compare:version] != NSOrderedAscending);
}

- (void)executeToken:(VT100Token *)token {
    NSString *command = token.string;
    NSData *data = token.savedData;
    if (_tmuxLogging) {
        [delegate_ tmuxPrintLine:[@"< " stringByAppendingString:command]];
    }
    if (![command hasPrefix:@"%output "] &&
        !currentCommand_) {
        TmuxLog(@"Read tmux command: \"%@\"", command);
    } else if (currentCommand_) {
        TmuxLog(@"Read command response: \"%@\"", command);
    }
    if (!acceptNotifications_) {
        TmuxLog(@"  Not accepting notifications");
    }
    // Work around a bug in tmux 1.8: if unlink-window causes the current
    // session to be destroyed, no end guard is printed but %exit may be
    // received.
    if (currentCommand_ &&
        ([command hasPrefix:@"%exit "] ||
         [command isEqualToString:@"%exit"])) {
      // Work around the bug by ending the command so the %exit can be
      // handled normally.
      [self stripLastNewline];
      [self currentCommandResponseFinishedWithError:NO];
    }

    NSString *endCommand = [NSString stringWithFormat:@"%%end %@", [currentCommand_ objectForKey:kCommandId]];
    NSString *errorCommand = [NSString stringWithFormat:@"%%error %@", [currentCommand_ objectForKey:kCommandId]];
    // TODO(georgen): It would be nice to include the command number and flags in
    // endCommand and errorCommand. Tmux 1.8 does not send flags.
    if (currentCommand_ && [command hasPrefix:endCommand]) {
        TmuxLog(@"End for command %@", currentCommand_);
        [self stripLastNewline];
        [self currentCommandResponseFinishedWithError:NO];
    } else if (currentCommand_ && [command hasPrefix:errorCommand]) {
        [self stripLastNewline];
        [self currentCommandResponseFinishedWithError:YES];
    } else if (currentCommand_) {
        [currentCommandResponse_ appendString:command];
        // Always append a newline; then at the end, remove the last one.
        [currentCommandResponse_ appendString:@"\n"];
        [currentCommandData_ appendData:data];
        [currentCommandData_ appendBytes:"\n" length:1];
    } else if ([command hasPrefix:@"%output "]) {
        if (acceptNotifications_) [self parseOutputCommandData:data];
    } else if ([command hasPrefix:@"%extended-output "]) {
        if (acceptNotifications_) [self parseExtendedOutputCommandData:data];
    } else if ([command hasPrefix:@"%layout-change "]) {
        if (acceptNotifications_) [self parseLayoutChangeCommand:command];
    } else if ([command hasPrefix:@"%window-add"]) {
        if (acceptNotifications_) [self parseWindowAddCommand:command];
    } else if ([command hasPrefix:@"%window-close"] ||
               [command hasPrefix:@"%unlinked-window-close"]) {
        if (acceptNotifications_) [self parseWindowCloseCommand:command];
    } else if ([command hasPrefix:@"%window-renamed"] ||
               [command hasPrefix:@"%unlinked-window-renamed"]) {
        if (acceptNotifications_) [self parseWindowRenamedCommand:command];
    } else if ([command hasPrefix:@"%unlinked-window-add"]) {
        if (acceptNotifications_) [self broadcastWindowChange];
    } else if ([command hasPrefix:@"%session-changed"]) {
        [self parseSessionChangeCommand:command];
    } else if ([command hasPrefix:@"%session-renamed"]) {
        if (acceptNotifications_) [self parseSessionRenamedCommand:command];
    } else if ([command hasPrefix:@"%sessions-changed"]) {
        if (acceptNotifications_) [self parseSessionsChangedCommand:command];
    } else if ([command hasPrefix:@"%noop"]) {
        TmuxLog(@"tmux noop: %@", command);
    } else if ([command hasPrefix:@"%window-pane-changed"]) {
        // New in tmux 2.5
        if (acceptNotifications_) [self parseWindowPaneChangedCommand:command];
    } else if ([command hasPrefix:@"%pause"]) {
        // New in tmux 3.2
        [self parsePauseCommand:command];
    } else if ([command hasPrefix:@"%subscription-changed "]) {
        // New in tmux 3.2
        if (acceptNotifications_) [self parseSubscriptionChangedCommand:command];
    } else if ([command hasPrefix:@"%continue"]) {
        // New in tmux 3.2. Don't care.
    } else if ([command hasPrefix:@"%session-window-changed"]) {
        if (acceptNotifications_) [self parseSessionWindowChangedCommand:command];
    } else if ([command hasPrefix:@"%client-session-changed"] ||  // client is now attached to a new session
               [command hasPrefix:@"%pane-mode-changed"]) {  // copy mode, etc
        // New in tmux 2.5. Don't care.
        TmuxLog(@"Ignore %@", command);
    } else if ([command hasPrefix:@"%exit "] ||
               [command isEqualToString:@"%exit"]) {
        TmuxLog(@"tmux exit message: %@", command);
        if ([strayMessages_ length] > 0) {
            [delegate_ tmuxPrintLine:@""];
            [delegate_ tmuxPrintLine:@"** ERROR **"];
            [delegate_ tmuxPrintLine:@"tmux exited with message:"];
            for (NSString *line in [strayMessages_ componentsSeparatedByString:@"\n"]) {
                if ([line length] > 0) {
                    [delegate_ tmuxPrintLine:line];
                }
            }
            [delegate_ tmuxPrintLine:@"********************************************************************************"];
        } else if ([command hasPrefix:@"%exit "]) {
            [delegate_ tmuxPrintLine:@"tmux exited unexpectedly."];
            [delegate_ tmuxPrintLine:command];
        }
        if ([self versionAtLeastDecimalNumberWithString:@"3.2"]) {
            [delegate_ tmuxWriteString:NEWLINE];
        }
        [self hostDisconnected];
    } else if ([command hasPrefix:@"%begin"]) {
        [self parseBegin:command];
    } else {
        if ([command hasPrefix:@"%"]) {
            DLog(@"Unrecognized notification: %@", command);
            return;
        }
        if (![iTermAdvancedSettingsModel tolerateUnrecognizedTmuxCommands]) {
            [delegate_ tmuxPrintLine:@"Unrecognized command from tmux. Did your ssh session die? The command was:"];
            [delegate_ tmuxPrintLine:command];
            [self hostDisconnected];
            return;
        }
        // We'll be tolerant of unrecognized commands.
        DLog(@"Unrecognized command \"%@\"", command);
        [strayMessages_ appendFormat:@"%@\n", command];
    }
}

- (NSString *)keyEncodedByte:(char)byte
{
    return [NSString stringWithFormat:@"0x%02x", (((int)byte) & 0xff)];
}

- (NSString *)stringForKeyEncodedData:(NSData *)data
{
    NSMutableString *encoded = [NSMutableString string];
    const char *bytes = [data bytes];
    for (int i = 0; i < data.length; i++) {
        if (i > 0) {
            [encoded appendString:@" "];
        }
        [encoded appendString:[self keyEncodedByte:bytes[i]]];
    }
    return encoded;
}

- (void)sendKeys:(NSString *)string toWindowPane:(int)windowPane {
    if ([self serverSupportsUTF8]) {
        // Send the actual code point of each character.
        [self sendCodePoints:[string codePoints] toWindowPane:windowPane];
    } else {
        // Send each byte of UTF-8 as a separate "keystroke". For tmux 2.1 and earlier.
        NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
        NSString *temp = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
        [self sendCodePoints:[temp codePoints] toWindowPane:windowPane];
    }
}

- (NSString *)firstSupplementaryPlaneCharacterInArray:(NSArray<NSNumber *> *)codePoints {
    NSUInteger index = [codePoints indexOfObjectPassingTest:^BOOL(NSNumber * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        return obj.integerValue > 0xffff;
    }];
    if (index == NSNotFound) {
        return nil;
    } else {
        UTF32Char c = [codePoints[index] integerValue];
        return [NSString stringWithLongCharacter:c];
    }
}

- (void)sendCodePoints:(NSArray<NSNumber *> *)codePoints toWindowPane:(int)windowPane {
    if (!codePoints.count) {
        return;
    }

    if (![self serverAcceptsSurrogatePairs]) {
        NSString *string = [self firstSupplementaryPlaneCharacterInArray:codePoints];
        if (string) {
            [delegate_ tmuxCannotSendCharactersInSupplementaryPlanes:string windowPane:windowPane];
            return;
        }
    }

    // Configure max lengths. Commands larger than 1024 bytes crash tmux 1.8.
    const NSUInteger maxLiteralCharacters = 1000;
    const NSUInteger maxHexCharacters = maxLiteralCharacters / 8;  // len(' C-Space') = 8
    NSDictionary<NSNumber *, NSNumber *> *maxLengths = @{
        @YES: @(maxLiteralCharacters),
        @NO: @(maxHexCharacters)
    };

    NSMutableArray *commands = [NSMutableArray array];
    void (^emitter)(NSArray<NSNumber *> * _Nonnull,
              NSNumber * _Nonnull) =
    ^(NSArray<NSNumber *> * _Nonnull codePoints,
      NSNumber * _Nonnull literal) {
        [commands addObject:[self dictionaryForSendKeysCommandWithCodePoints:codePoints
                                                                  windowPane:windowPane
                                                         asLiteralCharacters:literal.boolValue]];
    };
    NSNumber * _Nonnull(^classifier)(NSNumber * _Nonnull number) =
    ^NSNumber * _Nonnull(NSNumber * _Nonnull number) {
        return @([self canSendAsLiteralCharacter:number]);
    };

    [iTermRunLengthEncoder encodeArray:codePoints
                            maxLengths:maxLengths
                               emitter:emitter
                            classifier:classifier];

    [delegate_ tmuxSetSecureLogging:YES];
    [self sendCommandList:commands];
    [delegate_ tmuxSetSecureLogging:NO];
}

- (BOOL)doubleValue:(double)value1 isGreaterOrEqualTo:(double)value2 epsilon:(double)epsilon {
    return value1 - value2 >= -epsilon;
}

- (BOOL)serverSupportsUTF8 {
    return (self.minimumServerVersion != nil &&
            [self.minimumServerVersion compare:[NSDecimalNumber decimalNumberWithString:@"2.2"]] != NSOrderedAscending);
}

- (BOOL)serverAcceptsSurrogatePairs {
    NSDecimalNumber *version2_2 = [NSDecimalNumber decimalNumberWithString:@"2.2"];
    return !([self.minimumServerVersion isEqual:version2_2] && [self.maximumServerVersion isEqual:version2_2]);
}

- (BOOL)canSendAsLiteralCharacter:(NSNumber *)codePoint {
    const unichar c = codePoint.unsignedShortValue;
    if (c == '+' || c == '/' || c == ')' || c == ':' || c == ',' || c == '_') {
        return YES;
    }
    return isascii(c) && isalnum(c);
}

- (NSString *)numbersAsLiteralCharacters:(NSArray<NSNumber *> *)codePoints {
    NSMutableString *result = [NSMutableString stringWithCapacity:codePoints.count];
    for (NSNumber *number in codePoints) {
        [result appendFormat:@"%c", number.intValue];
    }
    return result;
}

- (NSDictionary *)dictionaryForSendKeysCommandWithCodePoints:(NSArray<NSNumber *> *)codePoints
                                                  windowPane:(int)windowPane
                                         asLiteralCharacters:(BOOL)asLiteralCharacters {
    NSString *value;
    if (asLiteralCharacters) {
        value = [self numbersAsLiteralCharacters:codePoints];
    } else {
        value = [codePoints numbersAsHexStrings];
    }
    NSString *command = [NSString stringWithFormat:@"send %@ %%%d %@",
                         asLiteralCharacters ? @"-lt" : @"-t", windowPane, value];
    NSDictionary *dict = [self dictionaryForCommand:command
                                     responseTarget:self
                                   responseSelector:@selector(noopResponseSelector:)
                                     responseObject:nil
                                              flags:kTmuxGatewayCommandShouldTolerateErrors];
    return dict;
}

- (void)detach {
    NSString *command = @"detach";
    if (detachSent_ && [self isTmuxUnresponsive]) {
        [delegate_ tmuxGatewayDidTimeOut];
        if (disconnected_) {
            return;
        }
    }
    [self sendCommand:command
       responseTarget:self
     responseSelector:@selector(noopResponseSelector:)
       responseObject:nil
                flags:kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate];
    detachSent_ = YES;
}

- (void)noopResponseSelector:(NSString *)response
{
}

- (NSDictionary *)dictionaryForCommand:(NSString *)command
                        responseTarget:(id)target
                      responseSelector:(SEL)selector
                        responseObject:(id)obj
                                 flags:(int)flags
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            command, kCommandString,
            target ? target : [NSNull null], kCommandTarget,
            selector ? (id) NSStringFromSelector(selector) : (id) [NSNull null], kCommandSelector,
            obj ? obj : [NSNull null], kCommandObject,
            [NSNumber numberWithInt:flags], kCommandFlags,
            nil];
}

- (void)enqueueCommandDict:(NSDictionary *)dict {
    if ([dict[kCommandFlags] intValue] & kTmuxGatewayCommandOfferToDetachIfLaggyDuplicate) {
        if ([self havePendingCommandEqualTo:dict[kCommandString]] && [self isTmuxUnresponsive]) {
            [delegate_ tmuxGatewayDidTimeOut];
            if (disconnected_) {
                return;
            }
        }
    }
    NSMutableDictionary *object = [[dict mutableCopy] autorelease];
    object[kCommandTimestamp] = @(CACurrentMediaTime());
    [commandQueue_ addObject:object];
}

- (BOOL)isTmuxUnresponsive {
    const CFTimeInterval now = CACurrentMediaTime();
    for (NSDictionary *dict in commandQueue_) {
        NSNumber *sentDate = dict[kCommandTimestamp];
        if (!sentDate) {
            continue;
        }
        if (now - sentDate.doubleValue > 5) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)havePendingCommandEqualTo:(NSString *)command {
    for (NSDictionary *dict in commandQueue_) {
        if ([dict[kCommandString] isEqual:command]) {
            return YES;
        }
    }
    return NO;
}

- (void)sendCommand:(NSString *)command responseTarget:(id)target responseSelector:(SEL)selector {
    // We tolerate errors when no target is specifed for bugward compatibility because such errors
    // used to be ignored purely by accident.
    [self sendCommand:command
       responseTarget:target
     responseSelector:selector
       responseObject:nil
                flags:(target == nil) ? kTmuxGatewayCommandShouldTolerateErrors : 0];
}

- (void)sendCommand:(NSString *)command
     responseTarget:(id)target
   responseSelector:(SEL)selector
     responseObject:(id)obj
              flags:(int)flags
{
    if (detachSent_ || disconnected_) {
        return;
    }
    NSString *commandWithNewline = [command stringByAppendingString:NEWLINE];
    NSDictionary *dict = [self dictionaryForCommand:commandWithNewline
                                     responseTarget:target
                                   responseSelector:selector
                                     responseObject:obj
                                              flags:flags];
    [self enqueueCommandDict:dict];
    if (disconnected_) {
        return;
    }
    TmuxLog(@"Send command: %@", commandWithNewline);
    [delegate_ tmuxWriteString:commandWithNewline];
    TmuxLog(@"Send command: %@", [dict objectForKey:kCommandString]);
}

- (void)sendCommandList:(NSArray *)commandDicts {
    [self sendCommandList:commandDicts initial:NO];
}

- (void)sendCommandList:(NSArray *)commandDicts initial:(BOOL)initial
{
    if (detachSent_ || disconnected_ || commandDicts.count == 0) {
        return;
    }
    NSMutableString *cmd = [NSMutableString string];
    NSString *sep = @"";
    TmuxLog(@"-- Begin command list --");
    for (NSDictionary *dict in commandDicts) {
        [cmd appendString:sep];
        [cmd appendString:[dict objectForKey:kCommandString]];
        NSMutableDictionary *amended = [NSMutableDictionary dictionaryWithDictionary:dict];
        if (dict == [commandDicts lastObject]) {
            [amended setObject:@YES forKey:kCommandIsLastInList];
        }
        [amended setObject:@YES forKey:kCommandIsInList];
        if (initial && dict == [commandDicts lastObject]) {
            [amended setObject:@YES forKey:kCommandIsInitial];
        }
        [self enqueueCommandDict:amended];
        if (disconnected_) {
            DLog(@"Aborting! Disconnected");
            return;
        }
        sep = @"; ";
        TmuxLog(@"Send command: %@", [dict objectForKey:kCommandString]);
    }
    TmuxLog(@"-- End command list --");
    [cmd appendString:NEWLINE];
    TmuxLog(@"Send command: %@", cmd);
    [delegate_ tmuxWriteString:cmd];
}

- (NSWindowController<iTermWindowController> *)window {
    return [delegate_ tmuxGatewayWindow];
}

- (iTermTmuxSubscriptionHandle *)subscribeToFormat:(NSString *)format
                                            target:(NSString *)target
                                             block:(void (^)(NSString *,
                                                             NSArray<NSString *> *))block {
    iTermTmuxSubscriptionHandle *handle = [[[iTermTmuxSubscriptionHandle alloc] initWithBlock:block] autorelease];
    NSString *subscribe = [NSString stringWithFormat:@"refresh-client -B '%@:%@:%@'",
                           handle.identifier,
                           target ?: @"",
                           format];
    _subscriptions[handle.identifier] = handle;
    [self sendCommand:subscribe
       responseTarget:self
     responseSelector:@selector(didSubscribe:handleID:)
       responseObject:handle.identifier
                flags:kTmuxGatewayCommandShouldTolerateErrors];
    return handle;
}

- (void)didSubscribe:(NSString *)result handleID:(NSString *)handleID {
    [_subscriptions[handleID] setInitialized:YES];
    if (result) {
        [_subscriptions[handleID] setValid];
    }
}

- (void)unsubscribe:(iTermTmuxSubscriptionHandle *)handle {
    if (!handle) {
        return;
    }
    if (!handle.isValid && handle.initialized) {
        // This tmux doesn't support subscriptions.
        return;
    }
    // Regardless of whether it was initialized, unsubscribe. That allows us to
    // unsubscribe before we get the response to subscribing in case it will
    // succeed.
    NSString *subscribe = [NSString stringWithFormat:@"refresh-client -B '%@'",
                           handle.identifier];
    [_subscriptions removeObjectForKey:handle.identifier];
    [self sendCommand:subscribe
       responseTarget:nil
     responseSelector:nil
       responseObject:nil
                flags:kTmuxGatewayCommandShouldTolerateErrors];
}

- (BOOL)supportsSubscriptions {
    return [self versionAtLeastDecimalNumberWithString:@"3.2"];
}

@end
