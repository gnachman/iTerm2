//
//  iTermEchoProbe.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/1/18.
//

#import "iTermEchoProbe.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "VT100Token.h"

typedef NS_ENUM(NSUInteger, iTermEchoProbeState) {
    iTermEchoProbeOff = 0,
    iTermEchoProbeWaiting = 1,
    iTermEchoProbeOneAsterisk = 2,
    iTermEchoProbeBackspaceOverAsterisk = 3,
    iTermEchoProbeSpaceOverAsterisk = 4,
    iTermEchoProbeBackspaceOverSpace = 5,
    iTermEchoProbeFailed = 6,
};

@implementation iTermEchoProbe {
    NSString *_password;
    iTermEchoProbeState _state;
}

- (void)setDelegate:(id<iTermEchoProbeDelegate>)delegate {
    if (delegate == self.delegate) {
        return;
    }
    [self.delegate echoProbeDelegateWillChange:delegate];
    _delegate = delegate;
}

- (void)beginProbeWithBackspace:(NSData *)backspace
                       password:(nonnull NSString *)password {
    _password = [password copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(timeout) object:nil];
    
    if (backspace) {
        // Try to figure out if we're at a shell prompt. Send a space character and immediately
        // backspace over it. If no output is received within a specified timeout, then go ahead and
        // send the password. Otherwise, ask for confirmation.
        [self.delegate echoProbe:self writeString:@" "];
        [self.delegate echoProbe:self writeData:backspace];
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

- (void)updateEchoProbeStateWithTokenCVector:(CVector *)vector {
    @synchronized(self) {
        if (_state == iTermEchoProbeOff || _state == iTermEchoProbeFailed) {
            return;
        }
        const int count = CVectorCount(vector);
        for (int i = 0; i < count; i++) {
            VT100Token *token = CVectorGetObject(vector, i);
            const iTermEchoProbeState previousState = _state;
            _state = iTermEchoProbeGetNextState(_state, token);
            if (_state != previousState) {
                DLog(@"%@ went %@->%@ because of token %@", self, @(previousState), @(_state), token);
            }
            if (_state == iTermEchoProbeOff || _state == iTermEchoProbeFailed) {
                break;
            }
        }
    }
}

- (BOOL)isActive {
    return _state != iTermEchoProbeOff;
}

iTermEchoProbeState iTermEchoProbeGetNextState(iTermEchoProbeState state, VT100Token *token) {
    switch (state) {
        case iTermEchoProbeOff:
        case iTermEchoProbeFailed:
            return state;
            
        case iTermEchoProbeWaiting:
            if (token->type == VT100_ASCIISTRING && [[token stringForAsciiData] isEqualToString:@"*"]) {
                return iTermEchoProbeOneAsterisk;
            } else {
                return iTermEchoProbeFailed;
            }
            
        case iTermEchoProbeOneAsterisk:
            if (token->type == VT100CC_BS ||
                (token->type == VT100CSI_CUB && token.csi->p[0] == 1)) {
                return iTermEchoProbeBackspaceOverAsterisk;
            } else {
                return iTermEchoProbeFailed;
            }
    
        case iTermEchoProbeBackspaceOverAsterisk:
            if (token->type == VT100_ASCIISTRING && [[token stringForAsciiData] isEqualToString:@" "]) {
                return iTermEchoProbeSpaceOverAsterisk;
            } else if (token->type == VT100CSI_EL && token.csi->p[0] == 0) {
                return iTermEchoProbeBackspaceOverSpace;
            } else {
                return iTermEchoProbeFailed;
            }
            
        case iTermEchoProbeSpaceOverAsterisk:
            if (token->type == VT100CC_BS) {
                return iTermEchoProbeBackspaceOverSpace;
            } else {
                return iTermEchoProbeFailed;
            }
            
        case iTermEchoProbeBackspaceOverSpace:
            return iTermEchoProbeFailed;
    }
}

- (void)enterPassword {
    const BOOL shouldSend = [self.delegate echoProbeShouldSendPassword:self];
    if (shouldSend) {
        [self.delegate echoProbe:self writeString:_password];
        [self.delegate echoProbe:self writeString:@"\n"];
    }
    [self.delegate echoProbeDidSucceed:self];
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
                [self.delegate echoProbeDidFail:self];
                break;
        }
        _state = iTermEchoProbeOff;
        _password = nil;
    }
}

@end
