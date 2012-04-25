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

#define NEWLINE @"\r\n"

#define TMUX_VERBOSE_LOGGING
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

    [super dealloc];
}

- (void)abortWithErrorMessage:(NSString *)message
{
    // TODO: be more forgiving of errors.
    NSLog(@"TmuxGateway parse errror: %@", message);
    [[NSAlert alertWithMessageText:@"A tmux protocol error occurred."
                     defaultButton:@"Ok"
                   alternateButton:@""
                       otherButton:@""
         informativeTextWithFormat:@"Reason: %@", message] runModal];
    [self detach];
}

- (NSData *)decodeHex:(NSString *)hexdata
{
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < hexdata.length; i += 2) {
        NSString *hex = [hexdata substringWithRange:NSMakeRange(i, 2)];
        unsigned scanned;
        if ([[NSScanner scannerWithString:hex] scanHexInt:&scanned]) {
            char c = scanned;
            [data appendBytes:&c length:1];
        }
    }
    return data;
}

- (void)parseOutputCommand:(NSString *)command
{
    // %output %<pane id> <hex data...><newline>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^[^ ]+ %([0-9]+) (.*)"];
    if (components.count != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%num hexdata): \"%@\"", command]];
        return;
    }
    int windowPane = [[components objectAtIndex:1] intValue];
    NSString *hexdata = [components objectAtIndex:2];
    if (hexdata.length % 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed output (odd number of hex bytes): \"%@\"", command]];
        return;
    }
    NSData *decodedCommand = [self decodeHex:hexdata];
    TmuxLog(@"Run tmux command: \"%%output %%%d %@", windowPane,
            [[[NSString alloc] initWithData:decodedCommand encoding:NSUTF8StringEncoding] autorelease]);
    [[[delegate_ tmuxController] sessionForWindowPane:windowPane]  tmuxReadTask:decodedCommand];
    state_ = CONTROL_STATE_READY;
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
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-add ([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-add id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowAddedWithId:[[components objectAtIndex:1] intValue]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseWindowCloseCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-close ([0-9]+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%window-close id): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxWindowClosedWithId:[[components objectAtIndex:1] intValue]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseWindowRenamedCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%window-renamed ([0-9]+) (.*)$"];
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
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-renamed (.+)$"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %%session-renamed name): \"%@\"", command]];
        return;
    }
    [delegate_ tmuxSessionRenamed:[components objectAtIndex:1]];
    state_ = CONTROL_STATE_READY;
}

- (void)parseSessionChangeCommand:(NSString *)command
{
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%session-changed ([0-9]+) (.+)$"];
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
   // Send a newline to ACK the exit command.
  [delegate_ tmuxWriteData:[NEWLINE dataUsingEncoding:NSUTF8StringEncoding]];
  [delegate_ tmuxHostDisconnected];
  state_ = CONTROL_STATE_DETACHED;
}

- (void)currentCommandResponseFinished
{
    id target = [currentCommand_ objectForKey:kCommandTarget];
    if (target) {
        SEL selector = NSSelectorFromString([currentCommand_ objectForKey:kCommandSelector]);
        id obj = [currentCommand_ objectForKey:kCommandObject];
        [target performSelector:selector
                     withObject:currentCommandResponse_
                     withObject:obj];
    }
    [currentCommand_ release];
    currentCommand_ = nil;
    [currentCommandResponse_ release];
    currentCommandResponse_ = nil;
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
    commandRange.length = newlineRange.location;
    // Command range doesn't include the newline.
    NSString *command = [[[NSString alloc] initWithData:[stream_ subdataWithRange:commandRange]
                                               encoding:NSUTF8StringEncoding] autorelease];
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

    if ([command isEqualToString:@"%end"]) {
        [self currentCommandResponseFinished];
    } else if (currentCommand_) {
        if (currentCommandResponse_.length) {
            [currentCommandResponse_ appendString:@"\n"];
        }
        [currentCommandResponse_ appendString:command];
    } else if ([command hasPrefix:@"%output "]) {
        [self parseOutputCommand:command];
    } else if ([command hasPrefix:@"%layout-change "]) {
        [self parseLayoutChangeCommand:command];
    } else if ([command hasPrefix:@"%window-add"]) {
        [self parseWindowAddCommand:command];
    } else if ([command hasPrefix:@"%window-close"]) {
        [self parseWindowCloseCommand:command];
    } else if ([command hasPrefix:@"%window-renamed"]) {
        [self parseWindowRenamedCommand:command];
    } else if ([command hasPrefix:@"%unlinked-window-add"] ||
               [command hasPrefix:@"%unlinked-window-close"]) {
        [self broadcastWindowChange];
    } else if ([command hasPrefix:@"%session-changed"]) {
        [self parseSessionChangeCommand:command];
    } else if ([command hasPrefix:@"%session-renamed"]) {
        [self parseSessionRenamedCommand:command];
    } else if ([command hasPrefix:@"%sessions-changed"]) {
        [self parseSessionsChangedCommand:command];
    } else if ([command hasPrefix:@"%noop"]) {
        TmuxLog(@"tmux noop: %@", command);
    } else if ([command hasPrefix:@"%exit "] ||
               [command isEqualToString:@"%exit"]) {
        TmuxLog(@"tmux exit message: %@", command);
        [self hostDisconnected];
    } else if ([command hasPrefix:@"%error"]) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Error: %@", command]];
    } else if ([command isEqualToString:@"%begin"]) {
        if (currentCommand_) {
            [self abortWithErrorMessage:@"%begin without %end"];
        } else if (!commandQueue_.count) {
            [self abortWithErrorMessage:@"%begin with empty command queue"];
        } else {
            currentCommand_ = [[commandQueue_ objectAtIndex:0] retain];
            [currentCommandResponse_ release];
            currentCommandResponse_ = [[NSMutableString alloc] init];
            [commandQueue_ removeObjectAtIndex:0];
        }
    } else {
        // We'll be tolerant of unrecognized commands.
        NSLog(@"Unrecognized command \"%@\"", command);
    }

    // Erase the just-handled command from the stream.
    [stream_ replaceBytesInRange:commandRange withBytes:"" length:0];

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
    NSString *command = [NSString stringWithFormat:@"send-keys -t %%%d %@",
                         windowPane, encoded];
    [self sendCommand:command
         responseTarget:self
         responseSelector:@selector(noopResponseSelector:)];
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
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            command, kCommandString,
            target, kCommandTarget,
            NSStringFromSelector(selector), kCommandSelector,
            obj, kCommandObject,
            nil];
}

- (void)enqueueCommandDict:(NSDictionary *)dict
{
    [commandQueue_ addObject:dict];
}

- (void)sendCommand:(NSString *)command responseTarget:(id)target responseSelector:(SEL)selector
{
    [self sendCommand:command
       responseTarget:target
     responseSelector:selector
       responseObject:nil];
}

- (void)sendCommand:(NSString *)command responseTarget:(id)target responseSelector:(SEL)selector responseObject:(id)obj
{
    if (detachSent_ || state_ == CONTROL_STATE_DETACHED) {
        return;
    }
    NSString *commandWithNewline = [command stringByAppendingString:NEWLINE];
    NSDictionary *dict = [self dictionaryForCommand:commandWithNewline
                                     responseTarget:target
                                   responseSelector:selector
                                     responseObject:obj];
    [self enqueueCommandDict:dict];
    [delegate_ tmuxWriteData:[commandWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendCommandList:(NSArray *)commandDicts
{
    if (detachSent_ || state_ == CONTROL_STATE_DETACHED) {
        return;
    }
    NSMutableString *cmd = [NSMutableString string];
    NSString *sep = @"";
    for (NSDictionary *dict in commandDicts) {
        [cmd appendString:sep];
        [cmd appendString:[dict objectForKey:kCommandString]];
        [self enqueueCommandDict:dict];
        sep = @"; ";
    }
    [cmd appendString:NEWLINE];
    [delegate_ tmuxWriteData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
