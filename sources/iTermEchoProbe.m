//
//  iTermEchoProbe.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/1/18.
//

#import "iTermEchoProbe.h"

#import "iTermAdvancedSettingsModel.h"

@implementation iTermEchoProbe {
    NSString *_password;
}

- (void)beginProbeWithBackspace:(NSData *)backspace
                       password:(nonnull NSString *)password {
    _password = [password copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
    
    if (backspace) {
        // Try to figure out if we're at a shell prompt. Send a space character and immediately
        // backspace over it. If no output is received within a specified timeout, then go ahead and
        // send the password. Otherwise, ask for confirmation.
        [self.delegate echoProbeWriteString:@" "];
        [self.delegate echoProbeWriteData:backspace];
        @synchronized(self) {
            _state = iTermEchoProbeWaiting;
        }
        [self performSelector:@selector(timeout)
                   withObject:nil
                   afterDelay:[iTermAdvancedSettingsModel echoProbeDuration]];
    } else {
        // Rare case: we don't know how to send a backspace. Just enter the password.
        [self enterPassword];
    }
}

- (void)updateEchoProbeStateWithBuffer:(char *)buffer length:(int)length {
    @synchronized(self) {
        if (_state == iTermEchoProbeOff) {
            return;
        }
        for (int i = 0; i < length; i++) {
            switch (_state) {
                case iTermEchoProbeOff:
                case iTermEchoProbeFailed:
                    return;
                    
                case iTermEchoProbeWaiting:
                    if (buffer[i] == '*') {
                        _state = iTermEchoProbeOneAsterisk;
                    } else {
                        _state = iTermEchoProbeFailed;
                        return;
                    }
                    break;
                    
                case iTermEchoProbeOneAsterisk:
                    if (buffer[i] == '\b') {
                        _state = iTermEchoProbeBackspaceOverAsterisk;
                    } else {
                        _state = iTermEchoProbeFailed;
                        return;
                    }
                    break;
                    
                case iTermEchoProbeBackspaceOverAsterisk:
                    if (buffer[i] == ' ') {
                        _state = iTermEchoProbeSpaceOverAsterisk;
                    } else {
                        _state = iTermEchoProbeFailed;
                        return;
                    }
                    break;
                    
                case iTermEchoProbeSpaceOverAsterisk:
                    if (buffer[i] == '\b') {
                        _state = iTermEchoProbeBackspaceOverSpace;
                    } else {
                        _state = iTermEchoProbeFailed;
                        return;
                    }
                    break;
                    
                case iTermEchoProbeBackspaceOverSpace:
                    _state = iTermEchoProbeFailed;
                    return;
            }
        }
    }
}

- (void)enterPassword {
    [self.delegate echoProbeWriteString:_password];
    [self.delegate echoProbeWriteString:@"\n"];
    _password = nil;
}

#pragma mark - Private

- (void)timeout {
    @synchronized (self) {
        switch (_state) {
            case iTermEchoProbeWaiting:
            case iTermEchoProbeBackspaceOverSpace:
                // It looks like we're at a password prompt. Send the password.
                [self enterPassword];
                break;
                
            case iTermEchoProbeFailed:
            case iTermEchoProbeOff:
            case iTermEchoProbeSpaceOverAsterisk:
            case iTermEchoProbeBackspaceOverAsterisk:
            case iTermEchoProbeOneAsterisk:
                [self.delegate echoProbeDidFail];
                break;
        }
        _state = iTermEchoProbeOff;
        _password = nil;
    }
}

@end
