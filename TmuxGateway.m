//
//  TmuxGateway.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxGateway.h"
#import "RegexKitLite.h"
#import "TmuxController.h"
#import "iTermApplicationDelegate.h"
#import "NSStringITerm.h"

NSString * const kTmuxGatewayErrorDomain = @"kTmuxGatewayErrorDomain";;
const int kTmuxGatewayCommandShouldTolerateErrors = (1 << 0);
const int kTmuxGatewayCommandWantsData = (1 << 1);
const int kTmuxGatewayCommandHasEndGuardBug = (1 << 2);

#define NEWLINE @"\r"

//#define TMUX_VERBOSE_LOGGING
#ifdef TMUX_VERBOSE_LOGGING
#define TmuxLog NSLog
#else
#define TmuxLog(args...) \
do { \
if (gDebugLogging) { \
DebugLog([NSString stringWithFormat:args]); \
} \
} while (0)
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

@implementation TmuxGateway

- (id)initWithDelegate:(NSObject<TmuxGatewayDelegate> *)delegate
{
    self = [super init];
    if (self) {
        delegate_ = delegate;
        state_ = CONTROL_STATE_READY;
        commandQueue_ = [[NSMutableArray alloc] init];
        stream_ = [[NSMutableData alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [commandQueue_ release];
    [stream_ release];
    [currentCommand_ release];
    [currentCommandResponse_ release];
    [currentCommandData_ release];

    [super dealloc];
}

- (void)abortWithErrorMessage:(NSString *)message
{
    // TODO: be more forgiving of errors.
    [[NSAlert alertWithMessageText:@"A tmux protocol error occurred."
                     defaultButton:@"Ok"
                   alternateButton:@""
                       otherButton:@""
         informativeTextWithFormat:@"Reason: %@", message] runModal];
    [self detach];
    [delegate_ tmuxHostDisconnected];  // Force the client to quit
    [stream_ replaceBytesInRange:NSMakeRange(0, stream_.length) withBytes:"" length:0];
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

    TmuxLog(@"Run tmux command: \"%%output %%%d %.*s", windowPane, [decodedData length], [decodedData bytes]);
    [[[delegate_ tmuxController] sessionForWindowPane:windowPane]  tmuxReadTask:decodedData];
    state_ = CONTROL_STATE_READY;

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
                                  layout:layout];
    state_ = CONTROL_STATE_READY;
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
    state_ = CONTROL_STATE_READY;
}

- (void)parseWindowCloseCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-close @([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-close id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowClosedWithId:[[components objectAtIndex:1] intValue]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseWindowRenamedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-renamed @([0-9]+) (.*)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-renamed id new_name): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowRenamedWithId:[[components objectAtIndex:1] intValue]
                                    to:[components objectAtIndex:2]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseSessionRenamedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-renamed \\$([0-9]+) (.+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-renamed id name): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSession:[[components objectAtIndex:1] intValue] renamed:[components objectAtIndex:2]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseSessionChangeCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-changed \\$([0-9]+) (.+)$"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-changed id name): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSessionChanged:[components objectAtIndex:2] sessionId:[[components objectAtIndex:1] intValue]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseSessionsChangedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%sessions-changed$"];
    if (components.count != 1) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%sessions-changed): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSessionsChanged];
    state_ = CONTROL_STATE_READY;
}

- (void)hostDisconnected
{
  [delegate_ tmuxHostDisconnected];
  [commandQueue_ removeAllObjects];
  state_ = CONTROL_STATE_DETACHED;
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
    [currentCommand_ release];
    currentCommand_ = nil;
    [currentCommandResponse_ release];
    currentCommandResponse_ = nil;
    [currentCommandData_ release];
    currentCommandData_ = nil;
}

- (void)parseBegin:(NSString *)command
{
    if ([command hasPrefix:@"%begin auto"]) {
        NSArray *components = [command captureComponentsMatchedByRegex:@"^%begin auto ([0-9 ]+)$"];
        if (components.count != 2) {
            [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%begin command_id): \"%@\"", command]];
            return;
        }
        TmuxLog(@"Begin auto response");
        currentCommand_ = [[NSMutableDictionary dictionaryWithObjectsAndKeys:
                               [components objectAtIndex:1], kCommandId,
                               nil] retain];
        [currentCommandResponse_ release];
        [currentCommandData_ release];
        currentCommandResponse_ = [[NSMutableString alloc] init];
        currentCommandData_ = [[NSMutableData alloc] init];
    } else {
        currentCommand_ = [[commandQueue_ objectAtIndex:0] retain];
        NSArray *components = [command captureComponentsMatchedByRegex:@"^%begin ([0-9 ]+)$"];
        if (components.count != 2) {
            [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%begin command_id): \"%@\"", command]];
            return;
        }
        NSString *commandId = [components objectAtIndex:1];
        [currentCommand_ setObject:commandId forKey:kCommandId];
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

- (BOOL)parseCommand
{
    NSRange newlineRange = NSMakeRange(NSNotFound, 0);
    unsigned char *streamBytes = [stream_ mutableBytes];
    for (int i = 0; i < stream_.length; i++) {
        if (streamBytes[i] == '\n') {
            newlineRange.location = i;
            newlineRange.length = 1;
            break;
        }
    }
    if (newlineRange.location == NSNotFound) {
        return NO;
    }
    NSRange commandRange;
    commandRange.location = 0;
    commandRange.length = newlineRange.location; // Command range doesn't include the newline.

    // Make a temp copy of the data, and remove linefeeds. Line drivers randomly add linefeeds.
    NSMutableData *data = [NSMutableData dataWithCapacity:commandRange.length];
    const char *bytes = [stream_ bytes] + commandRange.location;
    int lastIndex = 0;
    int i;
    for (i = 0; i < commandRange.length; i++) {
        if (bytes[i] == '\r') {
            if (i > lastIndex) {
                [data appendBytes:bytes + lastIndex length:i - lastIndex];
            }
            lastIndex = i + 1;
        }
    }
    if (i > lastIndex) {
        [data appendBytes:bytes + lastIndex length:i - lastIndex];
    }

    NSString *command = [[[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding] autorelease];
    if (!command) {
        // The command was not UTF-8. Unfortunately, this can happen. If tmux has a non-UTF-8
        // character in a pane, it will just output it in capture-pane.
        command = [[[NSString alloc] initWithUTF8DataIgnoringErrors:data] autorelease];
    }
    // At least on osx, the terminal driver adds \r at random places, sometimes adding two of them in a row!
    // We split on \n, which is safe, and just throw out any \r's that we see.
    command = [command stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    if (![command hasPrefix:@"%output "] &&
        !currentCommand_) {
        TmuxLog(@"Read tmux command: \"%@\"", command);
    } else if (currentCommand_) {
        TmuxLog(@"Read command response: \"%@\"", command);
    }
    // Advance range to include newline so we can chop it off
    commandRange.length += newlineRange.length;

    // Work around a bug in tmux 1.8: if unlink-window causes the current
    // session to be destroyed, no end guard is printed but %exit may be
    // received.
    int flags = [self currentCommandFlags];
    if (currentCommand_ &&
        (flags & kTmuxGatewayCommandHasEndGuardBug) &&
        ([command hasPrefix:@"%exit "] ||
         [command isEqualToString:@"%exit"])) {
      // Work around the bug by ending the command so the %exit can be
      // handled normally.
      [self stripLastNewline];
      [self currentCommandResponseFinishedWithError:NO];
    }

    NSString *endCommand = [NSString stringWithFormat:@"%%end %@", [currentCommand_ objectForKey:kCommandId]];
    NSString *errorCommand = [NSString stringWithFormat:@"%%error %@", [currentCommand_ objectForKey:kCommandId]];
    if (currentCommand_ && [command isEqualToString:endCommand]) {
        TmuxLog(@"End for command %@", currentCommand_);
        [self stripLastNewline];
        [self currentCommandResponseFinishedWithError:NO];
    } else if (currentCommand_ && [command isEqualToString:errorCommand]) {
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
    } else if ([command hasPrefix:@"%window-close"]) {
        if (acceptNotifications_) [self parseWindowCloseCommand:command];
    } else if ([command hasPrefix:@"%window-renamed"]) {
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
        [self hostDisconnected];
    } else if ([command hasPrefix:@"%begin"]) {
        if (currentCommand_) {
            [self abortWithErrorMessage:@"%begin without %end"];
        } else if (!commandQueue_.count) {
            [self abortWithErrorMessage:@"%begin with empty command queue"];
        } else {
            [self parseBegin:command];
        }
    } else {
        // We'll be tolerant of unrecognized commands.
        NSLog(@"Unrecognized command \"%@\"", command);
    }

    // Erase the just-handled command from the stream.
    if (stream_.length > 0) {  // length could be 0 if abortWtihErrorMessage: was called.
        [stream_ replaceBytesInRange:commandRange withBytes:"" length:0];
    }

    return YES;
}

- (NSData *)readTask:(NSData *)data
{
    [stream_ appendData:data];

    while ([stream_ length] > 0) {
        switch (state_) {
            case CONTROL_STATE_READY:
                if (![self parseCommand]) {
                    // Don't have a full command yet, need to read more.
                    return nil;
                }
                break;

            case CONTROL_STATE_DETACHED:
                data = [[stream_ copy] autorelease];
                [stream_ setLength:0];
                return data;
        }
    }
    return nil;
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

- (void)sendKeys:(NSData *)data toWindowPane:(int)windowPane
{
    NSString *encoded = [self stringForKeyEncodedData:data];
    [delegate_ tmuxSetSecureLogging:YES];
    NSString *command = [NSString stringWithFormat:@"send-keys -t %%%d %@",
                         windowPane, encoded];
    [self sendCommand:command
         responseTarget:self
         responseSelector:@selector(noopResponseSelector:)];
    [delegate_ tmuxSetSecureLogging:NO];
}

- (void)detach
{
    [self sendCommand:@"detach"
       responseTarget:self
     responseSelector:@selector(noopResponseSelector:)];
    detachSent_ = YES;
}

- (NSObject<TmuxGatewayDelegate> *)delegate
{
    return delegate_;
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
    if (detachSent_ || state_ == CONTROL_STATE_DETACHED) {
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
    [delegate_ tmuxWriteData:[commandWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
    TmuxLog(@"Send command: %@", [dict objectForKey:kCommandString]);
}

- (void)sendCommandList:(NSArray *)commandDicts {
    [self sendCommandList:commandDicts initial:NO];
}

- (void)sendCommandList:(NSArray *)commandDicts initial:(BOOL)initial
{
    if (detachSent_ || state_ == CONTROL_STATE_DETACHED) {
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
    [delegate_ tmuxWriteData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
