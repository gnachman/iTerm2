//
//  CapturedOutput.m
//  iTerm2
//
//  Created by George Nachman on 5/23/15.
//
//

#import "CapturedOutput.h"
#import "CaptureTrigger.h"
#import "iTermCapturedOutputMark.h"
#import "iTermPromise.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "VT100ScreenMark.h"

NSString *const kCapturedOutputLineKey = @"Line";
NSString *const kCapturedOutputValuesKey = @"Values";
// NSString *const kCapturedOutputTriggerHashKey_Deprecated = @"Trigger Hash";  // Deprecated
NSString *const kCaputredOutputCommandKey = @"Command";
NSString *const kCapturedOutputStateKey = @"State";
NSString *const kCapturedOutputMarkGuidKey = @"Mark Guid";
NSString *const kCapturedOutputAbsoluteLineNumberKey = @"Absolute Line Number";

@implementation CapturedOutput {
    CapturedOutput *_doppelganger;
}

@synthesize line = _line;
@synthesize values = _values;
@synthesize promisedCommand = _promisedCommand;
@synthesize state = _state;
@synthesize mark = _mark;
@synthesize absoluteLineNumber = _absoluteLineNumber;
@synthesize markGuid = _markGuid;

+ (instancetype)capturedOutputWithDictionary:(NSDictionary *)dict {
    CapturedOutput *capturedOutput = [[CapturedOutput alloc] init];
    if (capturedOutput) {
        capturedOutput.line = dict[kCapturedOutputLineKey];
        capturedOutput.values = dict[kCapturedOutputValuesKey];
        capturedOutput.absoluteLineNumber = [dict[kCapturedOutputAbsoluteLineNumberKey] longLongValue];
        capturedOutput.promisedCommand = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            NSString *value = [NSString castFrom:dict[kCaputredOutputCommandKey]];
            if (value) {
                [seal fulfill:value];
                return;
            }
            [seal reject:[NSError errorWithDomain:@"com.iterm2.captured-output" code:0 userInfo:nil]];
        }];
        capturedOutput.state = [dict[kCapturedOutputStateKey] boolValue];
        capturedOutput.markGuid = [dict[kCapturedOutputMarkGuidKey] copy];
    }
    return capturedOutput;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p line=%@ mark=%@ values=%@ %@>",
            NSStringFromClass([self class]),
            self,
            _line,
            _mark,
            _values,
            _isDoppelganger ? @"IsDop" : @"NotDop"];
}

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict =
    @{ kCapturedOutputLineKey: _line ?: [NSNull null],
       kCapturedOutputAbsoluteLineNumberKey: @(_absoluteLineNumber),
       kCapturedOutputValuesKey: _values ?: @[],
       kCaputredOutputCommandKey: _promisedCommand.maybeValue ?: [NSNull null],
       kCapturedOutputStateKey: @(_state),
       kCapturedOutputMarkGuidKey: _mark.guid ?: @"Mark Missing" };

    return [dict dictionaryByRemovingNullValues];
}

- (BOOL)canMergeFrom:(CapturedOutput *)other {
    return (other.absoluteLineNumber == self.absoluteLineNumber &&
            [other.line hasPrefix:self.line] &&
            [NSObject object:self.promisedCommand.maybeValue isEqualToObject:other.promisedCommand.maybeValue] &&
            self.state == other.state &&
            (self.markGuid == other.markGuid || [self.markGuid isEqualToString:other.markGuid]));
}

- (void)mergeFrom:(CapturedOutput *)other {
    self.line = other.line;
    self.values = other.values;
    self.promisedCommand = other.promisedCommand;
    self.state = other.state;
    self.markGuid = other.markGuid;
}

- (CapturedOutput *)copy {
    return [CapturedOutput capturedOutputWithDictionary:self.dictionaryValue];
}

- (id<CapturedOutputReading>)doppelganger {
    @synchronized([CapturedOutput class]) {
        assert(!_isDoppelganger);
        if (!_doppelganger) {
            _doppelganger = [self copy];
            _doppelganger->_isDoppelganger = YES;
        }
        return _doppelganger;
    }
}

- (NSString *)shortDebugDescription {
    return @"[CapOut]";
}


@end
