//
//  PasteContext.m
//  iTerm
//
//  Created by George Nachman on 3/12/13.
//
//

#import "PasteContext.h"
#import "iTermAdvancedSettingsModel.h"
#import "PasteEvent.h"

@interface PasteContext ()
@property(nonatomic, copy) NSString *bytesPerCallKey;
@property(nonatomic, copy) NSString *delayBetweenCallsKey;
@end

@implementation PasteContext

- (instancetype)initWithPasteEvent:(PasteEvent *)pasteEvent {
    self = [self initWithBytesPerCallPrefKey:pasteEvent.chunkKey
                                defaultValue:pasteEvent.defaultChunkSize
                    delayBetweenCallsPrefKey:pasteEvent.delayKey
                                defaultValue:pasteEvent.defaultDelay
                                  pasteEvent:pasteEvent];
    if (self) {
        self.blockAtNewline = !!(pasteEvent.flags & kPasteFlagsCommands);
        self.isUpload = pasteEvent.isUpload;
        self.progress = pasteEvent.progress;
    }
    return self;
}

- (instancetype)initWithBytesPerCallPrefKey:(NSString*)bytesPerCallKey
                     defaultValue:(int)bytesPerCallDefault
         delayBetweenCallsPrefKey:(NSString*)delayBetweenCallsKey
                     defaultValue:(float)delayBetweenCallsDefault
                                 pasteEvent:(PasteEvent *)pasteEvent {
    self = [super init];
    if (self) {
        _bytesPerCallKey = [bytesPerCallKey copy];
        _bytesPerCall = bytesPerCallDefault;
        _delayBetweenCallsKey = [delayBetweenCallsKey copy];
        _delayBetweenCalls = delayBetweenCallsDefault;
        _pasteEvent = pasteEvent;
        [self updateValues];
    }
    return self;
}

- (void)updateValues {
    if (_isUpload && [iTermAdvancedSettingsModel accelerateUploads]) {
        _bytesPerCall = 40960;
        _delayBetweenCalls = 0.01;
        return;
    }
    if (_bytesPerCallKey && [[NSUserDefaults standardUserDefaults] objectForKey:_bytesPerCallKey]) {
        _bytesPerCall = [[NSUserDefaults standardUserDefaults] integerForKey:_bytesPerCallKey];
    }
    if (_delayBetweenCallsKey && [[NSUserDefaults standardUserDefaults] objectForKey:_delayBetweenCallsKey]) {
        _delayBetweenCalls = [[NSUserDefaults standardUserDefaults] floatForKey:_delayBetweenCallsKey];
    }
}

- (void)setBytesPerCall:(int)newBytesPerCall {
    _bytesPerCall = newBytesPerCall;
    if (_bytesPerCallKey) {
        [[NSUserDefaults standardUserDefaults] setInteger:_bytesPerCall forKey:_bytesPerCallKey];
    }
}

- (void)setDelayBetweenCalls:(float)newDelayBetweenCalls {
    _delayBetweenCalls = newDelayBetweenCalls;
    if (_delayBetweenCallsKey) {
        [[NSUserDefaults standardUserDefaults] setFloat:newDelayBetweenCalls
                                                 forKey:_delayBetweenCallsKey];
    }
}

@end
