//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"
#import "CapturedOutput.h"
#import "NSObject+iTerm.h"
#import "NSStringiTerm.h"

NSString *const kMarkCodeKey = @"Code";
NSString *const kMarkCommandKey = @"Command";
NSString *const kMarkSessionGuidKey = @"Session Guid";
NSString *const kMarkStartDateKey = @"Start Date";
NSString *const kMarkEndDateKey = @"End Date";
NSString *const kMarkCapturedOutputKey = @"Captured Output";
NSString *const kMarkIsVisibleKey = @"Is Visible";
NSString *const kScreenMarkIsPrompt = @"Is Prompt";
NSString *const kMarkGuidKey = @"Guid";  // Not all kinds of marks have a guid

@implementation iTermMark {
    NSMutableArray *_capturedOutput;
}

@synthesize entry;
@synthesize code = _code;
@synthesize command = _command;
@synthesize sessionGuid = _sessionGuid;
@synthesize startDate = _startDate;
@synthesize endDate = _endDate;
@synthesize capturedOutput = _capturedOutput;
@synthesize delegate;

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _code = [dict[kMarkCodeKey] intValue];
        _sessionGuid = [[dict[kMarkSessionGuidKey] nilIfNull] copy];
        NSTimeInterval start = [dict[kMarkStartDateKey] doubleValue];
        if (start > 0) {
            _startDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:start] retain];
        }
        NSTimeInterval end = [dict[kMarkEndDateKey] doubleValue];
        if (end > 0) {
            _endDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:end] retain];
        }
        NSMutableArray *array = [NSMutableArray array];
        for (NSDictionary *capturedOutputDict in dict[kMarkCapturedOutputKey]) {
            [array addObject:[CapturedOutput capturedOutputWithDictionary:capturedOutputDict]];
        }
        _capturedOutput = [array retain];
        if (dict[kMarkCommandKey]) {
            _command = [[dict[kMarkCommandKey] nilIfNull] copy];
        }
    }
    return self;
}

- (void)dealloc {
    [_command release];
    [_startDate release];
    [_endDate release];
    [_capturedOutput release];
    [_sessionGuid release];
    [super dealloc];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p interval=%@ sessionGuid=%@>",
            self.class, self, self.entry.interval, self.sessionGuid];
}

- (void)setCommand:(NSString *)command {
    if (!_command) {
        [self.delegate markDidBecomeCommandMark:self];
    }
    [_command autorelease];
    _command = [command copy];
    self.startDate = [NSDate date];
}

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput {
    if (!_capturedOutput) {
        _capturedOutput = [[NSMutableArray alloc] init];
    }
    [_capturedOutput addObject:capturedOutput];
}

- (BOOL)isVisible {
    return YES;
}

- (NSArray *)capturedOutputDictionaries {
    NSMutableArray *array = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in _capturedOutput) {
        [array addObject:capturedOutput.dictionaryValue];
    }
    return array;
}

#pragma mark - IntervalTreeObject

- (NSDictionary *)dictionaryValue {
    return @{ kMarkCodeKey: @(_code),
              kMarkCommandKey: _command ?: [NSNull null],
              kMarkSessionGuidKey: self.sessionGuid ?: [NSNull null],
              kMarkStartDateKey: @([self.startDate timeIntervalSinceReferenceDate]),
              kMarkEndDateKey: @([self.endDate timeIntervalSinceReferenceDate]),
              kMarkCapturedOutputKey: [self capturedOutputDictionaries],
              kMarkIsVisibleKey: @(self.isVisible) };
}

@end

@implementation VT100ScreenMark

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super initWithDictionary:dict];
    if (self) {
        _isPrompt = [dict[kScreenMarkIsPrompt] boolValue];
        _guid = [dict[kMarkGuidKey] copy];
    }
    return self;
}

- (void)dealloc {
    [_guid release];
    [super dealloc];
}

- (NSString *)guid {
    if (!_guid) {
        self.guid = [NSString uuid];
    }
    return _guid;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [[[super dictionaryValue] mutableCopy] autorelease];
    dict[kScreenMarkIsPrompt] = @(_isPrompt);
    dict[kMarkGuidKey] = self.guid;
    return dict;
}

@end

@implementation iTermCapturedOutputMark

- (void)dealloc {
    [_guid release];
    [super dealloc];
}

- (NSString *)guid {
    if (!_guid) {
        self.guid = [NSString uuid];
    }
    return _guid;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super initWithDictionary:dict];
    if (self) {
        _guid = [dict[kMarkGuidKey] copy];
    }
    return self;
}

- (BOOL)isVisible {
    return NO;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [[[super dictionaryValue] mutableCopy] autorelease];
    dict[kMarkGuidKey] = self.guid;
    return dict;
}

@end
