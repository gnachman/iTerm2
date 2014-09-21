//
//  VT100TmuxParser.m
//  iTerm
//
//  Created by George Nachman on 3/10/14.
//
//

#import "VT100TmuxParser.h"
#import "NSMutableData+iTerm.h"

@interface VT100TmuxParser ()
@property(nonatomic, retain) NSString *currentCommandId;
@property(nonatomic, retain) NSString *currentCommandNumber;
@end

@implementation VT100TmuxParser {
    BOOL _inResponseBlock;
}

- (void)dealloc {
    [_currentCommandId release];
    [_currentCommandNumber release];
    [super dealloc];
}

- (void)decodeBytes:(unsigned char *)datap
             length:(int)datalen
          bytesUsed:(int *)rmlen
              token:(VT100Token *)result {
    if (datalen == 0) {
        return;
    }
    
    // Search for the end of the line.
    unsigned char *endOfLine = memchr(datap, '\n', datalen);
    if (!endOfLine) {
        result->type = VT100_WAIT;
        return;
    }
    
    int length = endOfLine - datap + 1;
    *rmlen = length;
    
    // Make a temp copy of the data, and remove linefeeds. Line drivers randomly add linefeeds.
    NSMutableData *data = [NSMutableData dataWithCapacity:length - 1];
    [data appendBytes:datap length:length - 1 excludingCharacter:'\r'];

    result.savedData = data;
    NSString *command = [[[NSString alloc] initWithData:data
                                               encoding:NSUTF8StringEncoding] autorelease];
    if (!command) {
        // The command was not UTF-8. Unfortunately, this can happen. If tmux has a non-UTF-8
        // character in a pane, it will just output it in capture-pane.
        command = [[[NSString alloc] initWithUTF8DataIgnoringErrors:data] autorelease];
    }
    result->type = TMUX_LINE;

    if (_inResponseBlock) {
        if ([command hasPrefix:@"%exit"]) {
            // Work around a bug in tmux 1.8: if unlink-window causes the current
            // session to be destroyed, no end guard is printed but %exit may be
            // received.
            // I submitted a patch to tmux on 4/6/13, but it's not clear how long the
            // workaround should stick around.
            // TODO: test tmux 1.9 and make sure this code can be removed, then remove it.
            result->type = TMUX_EXIT;
            _inResponseBlock = NO;
        } else if ([command hasPrefix:@"%end "] ||
                   [command hasPrefix:@"%error "]) {
            NSArray *parts = [command componentsSeparatedByString:@" "];
            if (parts.count >= 3 &&
                [_currentCommandId isEqual:parts[1]] &&
                [_currentCommandNumber isEqual:parts[2]]) {
                _inResponseBlock = NO;
            }
        }
    } else {
        if ([command hasPrefix:@"%begin"]) {
            NSArray *parts = [command componentsSeparatedByString:@" "];
            if (parts.count >= 3) {
                self.currentCommandId = parts[1];
                self.currentCommandNumber = parts[2];
                _inResponseBlock = YES;
            }
        } else if ([command hasPrefix:@"%exit"]) {
            result->type = TMUX_EXIT;
        }
    }
    result.string = command;
}

@end
