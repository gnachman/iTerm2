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
    [inputData_ release];

    [super dealloc];
}

- (void)abortWithErrorMessage:(NSString *)message
{
    // TODO: be more forgiving of errors.
    NSLog(@"TmuxGateway parse errror: %@", message);
    state_ = CONTROL_STATE_DETACHED;
    [[NSAlert alertWithMessageText:@"tmux disconnected unexpectedly"
                     defaultButton:@"Ok"
                   alternateButton:@""
                       otherButton:@""
         informativeTextWithFormat:@"Reason: %@", message] runModal];
}

- (void)parsePartialInputData
{
    // Move bytes from the beginning of stream into inputData_, but not beyond the trailing
    // newline.
    int availableBytes = [stream_ length];
    int neededBytes = length_ + 1 - [inputData_ length];
    int bytesToUse = MIN(neededBytes, availableBytes);
    [inputData_ appendBytes:[stream_ bytes]
                     length:bytesToUse];
    [stream_ replaceBytesInRange:NSMakeRange(0, bytesToUse)
                       withBytes:""
                          length:0];
    const BOOL haveAllInput = ([inputData_ length] == length_ + 1);
    char lastByteInInput = 0;
    const char *inputBytes = [inputData_ bytes];
    if ([inputData_ length] > 0) {
        lastByteInInput = inputBytes[inputData_.length - 1];
    }
    const char *streamBytes = [stream_ bytes];
    char firstByteAfterInput = 0;
    if ([stream_ length] > 0) {
        firstByteAfterInput = streamBytes[0];
    }
    // If the input is fully read and we have a CR or CRLF after it...
    if ((haveAllInput && lastByteInInput == '\n') ||
        (haveAllInput && lastByteInInput == '\r' && firstByteAfterInput == '\n')){
        // There are enough bytes in the stream to cover all of length plus a newline.
        // Truncate the trailing newline and process.
        [inputData_ setLength:inputData_.length - 1];
        [[[delegate_ tmuxController] sessionForWindow:window_ pane:windowPane_]  tmuxReadTask:inputData_];
        if (lastByteInInput == '\r') {
            // Line terminated with CR LF (\r\n).
            // Eat up one byte from the start of the stream_ to get rid of the LF
            [stream_ replaceBytesInRange:NSMakeRange(0, 1) withBytes:"" length:0];
        }
        state_ = CONTROL_STATE_READY;
    } else {
        // Keep reading next time.
        state_ = CONTROL_STATE_READING_DATA;
    }        
}

- (void)parseOutputCommand:(NSString *)command
{
    // %output <window>.<pane> <length> <data...><newline>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^[^ ]+ +([0-9]+)\\.([0-9]+) ([0-9]+)"];
    if (components.count != 4) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected num.num num): \"%@\"", command]];
        return;
    }
    window_ = [[components objectAtIndex:1] intValue];
    windowPane_ = [[components objectAtIndex:2] intValue];
    length_ = [[components objectAtIndex:3] intValue];

    // Find the offset of the byte after the third space, if any
    int numSpaces = 0;
    const char *bytes = [stream_ bytes];
    int i;
    for (i = 0; numSpaces < 3 && i < [stream_ length]; i++) {
        if (bytes[i] == ' ') {
            ++numSpaces;
        }
    }
    if (numSpaces != 3) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected 3 spaces, got %d): \"%@\"", numSpaces, command]];
        return;
    }
    // Yank everything up to the beginning of the data out of the stream.
    [stream_ replaceBytesInRange:NSMakeRange(0, i)
                       withBytes:""
                          length:0];
    
    [inputData_ release];
    inputData_ = [[NSMutableData alloc] init];
    [self parsePartialInputData];
}

- (void)parseLayoutChangeCommand:(NSString *)command
{
    // %layout-change <window><newline>
    NSArray *components = [command captureComponentsMatchedByRegex:@"^[^ ]* ([0-9]+)"];
    if (components.count != 2) {
        [self abortWithErrorMessage:[NSString stringWithFormat:@"Malformed command (expected an int arg): \"%@\"", command]];
        return;
    }
    window_ = [[components objectAtIndex:1] intValue];
    [delegate_ tmuxUpdateLayoutForWindow:window_];
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
    SEL selector = NSSelectorFromString([currentCommand_ objectForKey:kCommandSelector]);
    [target performSelector:selector withObject:currentCommandResponse_];
    [currentCommand_ release];
    currentCommand_ = nil;
    [currentCommandResponse_ release];
    currentCommandResponse_ = nil;
}

- (void)parseCommand
{
    NSRange crRange = [stream_ rangeOfData:[NSData dataWithBytes:"\n" length:1]
                                   options:0
                                     range:NSMakeRange(0, stream_.length)];
    NSRange crlfRange = [stream_ rangeOfData:[NSData dataWithBytes:"\r\n" length:2]
                                     options:0
                                       range:NSMakeRange(0, stream_.length)];

    NSRange newlineRange;
    if (crRange.location == NSNotFound && crlfRange.location == NSNotFound) {
        // No newline of any kind
        return;
    } else if (crRange.location != NSNotFound && crlfRange.location != NSNotFound) {
        // CRLF & CR - use the first one
        if (crRange.location < crlfRange.location) {
            newlineRange = crRange;
        } else {
            newlineRange = crlfRange;
        }
    } else {
        // CR only
        newlineRange = crRange;
    }  // Only 3 cases because the fourth case (crlf & !cr) is impossible
    
    if (newlineRange.location == 0) {
        NSLog(@"tmux: Empty command");
        [stream_ replaceBytesInRange:newlineRange withBytes:"" length:0];
        return;
    }
    
    NSRange commandRange;
    commandRange.location = 0;
    commandRange.length = newlineRange.location;
    // Command range doesn't include the newline.
    NSString *command = [[[NSString alloc] initWithData:[stream_ subdataWithRange:commandRange]
                                               encoding:NSUTF8StringEncoding] autorelease];
    NSLog(@"Read tmux command: \"%@\"", command);
    // Advance range to include newline so we can chop it off
    commandRange.length += newlineRange.length;
    
    BOOL doTruncation = YES;

    if ([command isEqualToString:@"%end"]) {
        [self currentCommandResponseFinished];
    } else if (currentCommand_) {
        if (currentCommandResponse_.length) {
            [currentCommandResponse_ appendString:@"\n"];
        }
        [currentCommandResponse_ appendString:command];
    } else if ([command hasPrefix:@"%output "]) {
        [self parseOutputCommand:command];
        doTruncation = NO;
    } else if ([command hasPrefix:@"%layout-change "]) {
        [self parseLayoutChangeCommand:command];
    } else if ([command hasPrefix:@"%windows-change"]) {
        [self parseWindowsChangeCommand:command];
    } else if ([command hasPrefix:@"%noop"]) {
        NSLog(@"tmux noop: %@", command);
    } else if ([command hasPrefix:@"%exit "]) {
        NSLog(@"tmux exit message: %@", command);
        [self hostDisconnected];
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
    
    // Erase the just-handled command from the stream (except for %output,
    // which is special).
    if (doTruncation) {
        [stream_ replaceBytesInRange:commandRange withBytes:"" length:0];
    }
}
    
- (NSData *)readTask:(NSData *)data
{
    [stream_ appendData:data];

    while ([stream_ length] > 0) {
        switch (state_) {
            case CONTROL_STATE_READY:
                [self parseCommand];
                break;
                
            case CONTROL_STATE_READING_DATA:
                [self parsePartialInputData];
                break;
                
            case CONTROL_STATE_DETACHED:
                data = [[stream_ copy] autorelease];
                [stream_ setLength:0];
                return data;
        }
    }
    return nil;
}

- (void)sendCommand:(NSString *)command responseTarget:(id)target responseSelector:(SEL)selector
{
    NSString *commandWithNewline = [command stringByAppendingString:@"\n"];
    NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                          commandWithNewline, kCommandString,
                          target, kCommandTarget,
                          NSStringFromSelector(selector), kCommandSelector,
                          nil];
    [commandQueue_ addObject:dict];
    [delegate_ tmuxWriteData:[commandWithNewline dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
