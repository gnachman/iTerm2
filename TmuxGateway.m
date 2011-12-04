//
//  TmuxGateway.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TmuxGateway.h"
#import "RegexKitLite.h"
#import "TmuxController.h"

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

- (NSData *)decodeBase64:(NSString *)b64data
{
    // TODO: This is a hack because I don't have a b64 implementation handy on vacation
    NSMutableData *data = [NSMutableData data];
    for (int i = 0; i < b64data.length; i += 2) {
        NSString *hex = [b64data substringWithRange:NSMakeRange(i, 2)];
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
    // %output <window>.<pane> <b64 data...><newline>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^[^ ]+ +([0-9]+)\\.([0-9]+) (.*)"];
    if (components.count != 4) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected num.num b64data): \"%@\"", command]];
        return;
    }
    int window = [[components objectAtIndex:1] intValue];
    int windowPane = [[components objectAtIndex:2] intValue];
    NSString *base64data = [components objectAtIndex:3];
    NSData *decodedCommand = [self decodeBase64:base64data];
    NSLog(@"Run tmux command: \"%%output %d.%d %@", window, windowPane,
          [[[NSString alloc] initWithData:decodedCommand encoding:NSUTF8StringEncoding] autorelease]);
    [[[delegate_ tmuxController] sessionForWindow:window pane:windowPane]  tmuxReadTask:decodedCommand];
    state_ = CONTROL_STATE_READY;
}

- (void)parseLayoutChangeCommand:(NSString *)command
{
    // %layout-change <window> <int>x<int> <layout>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^%layout-change ([0-9]+) ([0-9]+)x([0-9]+) (.*)"];
    if (components.count != 5) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected %layout-change <window> <int>x<int> <layout>): \"%@\"",
                                     command]];
        return;
    }
    int window = [[components objectAtIndex:1] intValue];
    NSSize size = NSMakeSize([[components objectAtIndex:2] intValue],
                             [[components objectAtIndex:3] intValue]);
    NSString *layout = [components objectAtIndex:4];
    [delegate_ tmuxUpdateLayoutForWindow:window
                                    size:size
                                  layout:layout];
    state_ = CONTROL_STATE_READY;
}

- (void)parseWindowsChangeCommand:(NSString *)command
{
    [delegate_ tmuxWindowsDidChange];
    state_ = CONTROL_STATE_READY;
}

- (void)hostDisconnected
{
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
    NSRange newlineRange = [stream_ rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                        options:0
                                          range:NSMakeRange(0, stream_.length)];
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
        NSLog(@"Read tmux command: \"%@\"", command);
    } else if (currentCommand_) {
        NSLog(@"Read command response: \"%@\"", command);
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
    } else if ([command hasPrefix:@"%windows-change"]) {
        [self parseWindowsChangeCommand:command];
    } else if ([command hasPrefix:@"%noop"]) {
        NSLog(@"tmux noop: %@", command);
    } else if ([command hasPrefix:@"%exit "]) {
        NSLog(@"tmux exit message: %@", command);
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
    return [NSString stringWithFormat:@"%02x", (int)byte];
}

- (NSString *)stringForKeyEncodedData:(NSData *)data
{
    NSMutableString *encoded = [NSMutableString string];
    const char *bytes = [data bytes];
    for (int i = 0; i < data.length; i++) {
        [encoded appendString:[self keyEncodedByte:bytes[i]]];
    }
    return encoded;
}

- (void)sendKeys:(NSData *)data toWindow:(int)window windowPane:(int)windowPane
{
    NSString *encoded = [self stringForKeyEncodedData:data];
    NSString *command = [NSString stringWithFormat:@"send-keys -h -t %d.%d %@",
                         window, windowPane, encoded];
    [self sendCommand:command
         responseTarget:self
         responseSelector:@selector(noopResponseSelector:)];
}

- (void)detach
{
    [self sendCommand:@"detach"
       responseTarget:self
     responseSelector:@selector(noopResponseSelector:)];
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
    NSString *commandWithNewline = [command stringByAppendingString:@"\n"];
    NSDictionary *dict = [self dictionaryForCommand:commandWithNewline
                                     responseTarget:target
                                   responseSelector:selector
                                     responseObject:obj];
    [self enqueueCommandDict:dict];
    [delegate_ tmuxWriteData:[commandWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)sendCommandList:(NSArray *)commandDicts
{
    NSMutableString *cmd = [NSMutableString string];
    NSString *sep = @"";
    for (NSDictionary *dict in commandDicts) {
        [cmd appendString:sep];
        [cmd appendString:[dict objectForKey:kCommandString]];
        [self enqueueCommandDict:dict];
        sep = @"; ";
    }
    [cmd appendString:@"\n"];
    [delegate_ tmuxWriteData:[cmd dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
