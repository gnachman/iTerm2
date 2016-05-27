//
//  TmuxGateway.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxGateway.h"

#import "iTermApplicationDelegate.h"
#import "iTermAdvancedSettingsModel.h"
#import "TmuxController.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"
#import "VT100Token.h"

NSString * const kTmuxGatewayErrorDomain = @"kTmuxGatewayErrorDomain";;
const int kTmuxGatewayCommandShouldTolerateErrors = (1 << 0);
const int kTmuxGatewayCommandWantsData = (1 << 1);

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

    BOOL detachSent_;
    BOOL acceptNotifications_;  // Initially NO. When YES, respond to notifications.
    NSMutableString *strayMessages_;
    
    // When we get the first %begin-%{end,error} we notify the delegate. Until that happens, this is
    // set to NO.
    BOOL _initialized;
}

@synthesize delegate = delegate_;

- (instancetype)initWithDelegate:(id<TmuxGatewayDelegate>)delegate {
    self = [super init];
    if (self) {
        delegate_ = delegate;
        commandQueue_ = [[NSMutableArray alloc] init];
        strayMessages_ = [[NSMutableString alloc] init];
    }
    return self;
}

- (void)dealloc {
    [commandQueue_ release];
    [currentCommand_ release];
    [currentCommandResponse_ release];
    [currentCommandData_ release];
    [strayMessages_ release];

    [super dealloc];
}

- (void)abortWithErrorMessage:(NSString *)message
{
    [self abortWithErrorMessage:[NSString stringWithFormat:@"Reason: %@", message]
                          title:@"A tmux protocol error occurred."];
}

- (void)abortWithErrorMessage:(NSString *)message title:(NSString *)title
{
    // TODO: be more forgiving of errors.
    [[NSAlert alertWithMessageText:title
                     defaultButton:@"OK"
                   alternateButton:@""
                       otherButton:@""
         informativeTextWithFormat:@"%@", message] runModal];
    [self detach];
    [delegate_ tmuxHostDisconnected];  // Force the client to quit
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

- (void)parseOutputCommandData:(NSData *)input
{
    // Null terminate so we can do some string parsing without too much pain.
    NSMutableData *data = [NSMutableData dataWithData:input];
    [data appendBytes:"" length:1];

    // This one is tricky to parse because the string version of the command could have bogus UTF-8.
    // %output %<pane id> <data...><newline>
    const char *command = [data bytes];
    char *space = strchr(command, ' ');
    if (!space) {
        goto error;
    }
    const char *outputCommand = "%output";
    if (strncmp(outputCommand, command, strlen(outputCommand))) {
        goto error;
    }
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

    NSData *decodedData = [self decodeEscapedOutput:space + 1];

    TmuxLog(@"Run tmux command: \"%%output %%%d %.*s", windowPane, (int)[decodedData length], [decodedData bytes]);
    [[[delegate_ tmuxController] sessionForWindowPane:windowPane] tmuxReadTask:decodedData];

    return;
error:
    [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%num data): \"%s\"", command]];
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
                                  zoomed:nil];
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
    [delegate_ tmuxWindowRenamedWithId:[[components objectAtIndex:1] intValue]
                                    to:[components objectAtIndex:2]];
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

- (void)hostDisconnected
{
    [delegate_ tmuxHostDisconnected];
    [commandQueue_ removeAllObjects];
    disconnected_ = YES;
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

- (void)currentCommandResponseFinishedWithError:(BOOL)withError
{
    id target = [self currentCommandTarget];
    if (target) {
        SEL selector = [self currentCommandSelector];
        id obj = [self currentCommandObject];
        if (withError) {
            if ([self currentCommandFlags] & kTmuxGatewayCommandShouldTolerateErrors) {
                [target performSelector:selector
                             withObject:nil
                             withObject:obj];
            } else {
                [self abortWithErrorMessage:[NSString stringWithFormat:@"Error: %@", currentCommand_]];
                return;
            }
        } else {
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
    }
    if ([[currentCommand_ objectForKey:kCommandIsInitial] boolValue]) {
        acceptNotifications_ = YES;
    }
    if (!_initialized) {
        _initialized = YES;
        if (withError) {
            [delegate_ tmuxInitialCommandDidFailWithError:currentCommandResponse_];
        } else {
            [delegate_ tmuxInitialCommandDidCompleteSuccessfully];
        }
    }

    [currentCommand_ release];
    currentCommand_ = nil;
    [currentCommandResponse_ release];
    currentCommandResponse_ = nil;
    [currentCommandData_ release];
    currentCommandData_ = nil;
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
        currentCommand_ = [commandQueue_[0] retain];
        NSString *commandId = components[1];
        currentCommand_[kCommandId] = commandId;
        TmuxLog(@"Begin response to %@", [currentCommand_ objectForKey:kCommandString]);
        [currentCommandResponse_ release];
        [currentCommandData_ release];
        currentCommandResponse_ = [[NSMutableString alloc] init];
        currentCommandData_ = [[NSMutableData alloc] init];
        [commandQueue_ removeObjectAtIndex:0];
    }
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

- (void)executeToken:(VT100Token *)token {
    NSString *command = token.string;
    NSData *data = token.savedData;
    if (_tmuxLogging) {
        [delegate_ tmuxPrintLine:command];
    }
    if (![command hasPrefix:@"%output "] &&
        !currentCommand_) {
        TmuxLog(@"Read tmux command: \"%@\"", command);
    } else if (currentCommand_) {
        TmuxLog(@"Read command response: \"%@\"", command);
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
        [self hostDisconnected];
    } else if ([command hasPrefix:@"%begin"]) {
        [self parseBegin:command];
    } else {
        if (![command hasPrefix:@"%"] && ![iTermAdvancedSettingsModel tolerateUnrecognizedTmuxCommands]) {
            [delegate_ tmuxPrintLine:@"Unrecognized command from tmux. Did your ssh session die? The command was:"];
            [delegate_ tmuxPrintLine:command];
            [self hostDisconnected];
        } else {
            // We'll be tolerant of unrecognized commands.
            NSLog(@"Unrecognized command \"%@\"", command);
            [strayMessages_ appendFormat:@"%@\n", command];
        }
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
    [self sendCodePoints:[string codePoints] toWindowPane:windowPane];
}

- (void)sendCodePoints:(NSArray<NSNumber *> *)codePoints toWindowPane:(int)windowPane {
    if (!codePoints.count) {
        return;
    }
    
    // Send multiple small send-keys commands because commands longer than 1024 bytes crash tmux 1.8.
    NSMutableArray *commands = [NSMutableArray array];
    const NSUInteger stride = 80;
    for (NSUInteger start = 0; start < codePoints.count; start += stride) {
        NSUInteger length = MIN(stride, codePoints.count - start);
        NSRange range = NSMakeRange(start, length);
        NSArray *subarray = [codePoints subarrayWithRange:range];
        [commands addObject:[self dictionaryForSendKeysCommandWithCodePoints:subarray windowPane:windowPane]];
    }

    [delegate_ tmuxSetSecureLogging:YES];
    [self sendCommandList:commands];
    [delegate_ tmuxSetSecureLogging:NO];
}

- (NSDictionary *)dictionaryForSendKeysCommandWithCodePoints:(NSArray<NSNumber *> *)codePoints
                                                  windowPane:(int)windowPane {
    NSString *command = [NSString stringWithFormat:@"send-keys -t %%%d %@",
                         windowPane, [codePoints numbersAsHexStrings]];
    NSDictionary *dict = [self dictionaryForCommand:command
                                     responseTarget:self
                                   responseSelector:@selector(noopResponseSelector:)
                                     responseObject:nil
                                              flags:0];
    return dict;
}

- (void)detach
{
    [self sendCommand:@"detach"
       responseTarget:self
     responseSelector:@selector(noopResponseSelector:)];
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

- (void)enqueueCommandDict:(NSDictionary *)dict
{
    [commandQueue_ addObject:[NSMutableDictionary dictionaryWithDictionary:dict]];
}

- (void)sendCommand:(NSString *)command responseTarget:(id)target responseSelector:(SEL)selector
{
    [self sendCommand:command
       responseTarget:target
     responseSelector:selector
       responseObject:nil
                flags:0];
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
            [amended setObject:[NSNumber numberWithBool:YES] forKey:kCommandIsLastInList];
        }
        [amended setObject:[NSNumber numberWithBool:YES] forKey:kCommandIsInList];
        if (initial && dict == [commandDicts lastObject]) {
            [amended setObject:[NSNumber numberWithBool:YES] forKey:kCommandIsInitial];
        }
        [self enqueueCommandDict:amended];
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

@end
