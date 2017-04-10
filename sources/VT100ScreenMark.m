//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"
#import "CapturedOutput.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"

static NSString *const kScreenMarkIsPrompt = @"Is Prompt";
static NSString *const kMarkGuidKey = @"Guid";
static NSString *const kMarkCapturedOutputKey = @"Captured Output";
static NSString *const kMarkCommandKey = @"Command";
static NSString *const kMarkCodeKey = @"Code";
static NSString *const kMarkStartDateKey = @"Start Date";
static NSString *const kMarkEndDateKey = @"End Date";
static NSString *const kMarkSessionGuidKey = @"Session Guid";
static NSString *const kMarkPromptRange = @"Prompt Range";
static NSString *const kMarkCommandRange = @"Command Range";
static NSString *const kMarkOutputStart = @"Output Start";

@implementation VT100ScreenMark {
    NSMutableArray *_capturedOutput;
}

+ (NSMapTable *)registry {
    static NSMapTable *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality)
                                             valueOptions:(NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality)
                                                 capacity:1024];
    });
    return registry;
}

+ (VT100ScreenMark *)markWithGuid:(NSString *)guid {
    return [self.registry objectForKey:guid];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[self.class registry] setObject:self forKey:self.guid];
        _promptRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _commandRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _outputStart = VT100GridAbsCoordMake(-1, -1);
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super initWithDictionary:dict];
    if (self) {
        _code = [dict[kMarkCodeKey] intValue];
        _isPrompt = [dict[kScreenMarkIsPrompt] boolValue];
        if ([dict[kMarkGuidKey] isKindOfClass:[NSString class]]) {
            _guid = [dict[kMarkGuidKey] copy];
        } else {
            _guid = [[NSString uuid] retain];
        }
        _sessionGuid = [dict[kMarkSessionGuidKey] copy];
        NSTimeInterval start = [dict[kMarkStartDateKey] doubleValue];
        if (start > 0) {
            _startDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:start] retain];
        }
        NSTimeInterval end = [dict[kMarkEndDateKey] doubleValue];
        if (end > 0) {
            _endDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:end] retain];
        }
        NSMutableArray *array = [NSMutableArray array];
        _capturedOutput = [array retain];
        for (NSDictionary *capturedOutputDict in dict[kMarkCapturedOutputKey]) {
            [array addObject:[CapturedOutput capturedOutputWithDictionary:capturedOutputDict]];
        }
        if ([dict[kMarkCommandKey] isKindOfClass:[NSString class]]) {
            _command = [dict[kMarkCommandKey] copy];
        }
        if (dict[kMarkPromptRange]) {
            _promptRange = [dict[kMarkPromptRange] gridAbsCoordRange];
        } else {
            _promptRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        }
        if (dict[kMarkCommandRange]) {
            _commandRange = [dict[kMarkCommandRange] gridAbsCoordRange];
        } else {
            _commandRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        }
        if (dict[kMarkOutputStart]) {
            _outputStart = [dict[kMarkOutputStart] gridAbsCoord];
        } else {
            _outputStart = VT100GridAbsCoordMake(-1, -1);
        }
        [[self.class registry] setObject:self forKey:self.guid];
    }
    return self;
}

- (void)dealloc {
    [[self.class registry] removeObjectForKey:_guid];
    [_guid release];
    [_capturedOutput release];
    [_command release];
    [_startDate release];
    [_endDate release];
    [_sessionGuid release];
    [super dealloc];
}

- (NSString *)guid {
    if (!_guid) {
        self.guid = [NSString uuid];
    }
    return _guid;
}

- (NSArray *)capturedOutputDictionaries {
    NSMutableArray *array = [NSMutableArray array];
    for (CapturedOutput *capturedOutput in _capturedOutput) {
        [array addObject:capturedOutput.dictionaryValue];
    }
    return array;
}

- (NSDictionary *)dictionaryValue {
    NSMutableDictionary *dict = [[[super dictionaryValue] mutableCopy] autorelease];
    dict[kScreenMarkIsPrompt] = @(_isPrompt);
    dict[kMarkGuidKey] = self.guid;
    dict[kMarkCapturedOutputKey] = [self capturedOutputDictionaries];
    dict[kMarkCodeKey] = @(_code);
    dict[kMarkCommandKey] = _command ?: [NSNull null];
    dict[kMarkStartDateKey] = @([self.startDate timeIntervalSinceReferenceDate]);
    dict[kMarkEndDateKey] = @([self.endDate timeIntervalSinceReferenceDate]);
    dict[kMarkSessionGuidKey] = self.sessionGuid ?: [NSNull null];
    dict[kMarkPromptRange] = [NSDictionary dictionaryWithGridAbsCoordRange:_promptRange];
    dict[kMarkCommandRange] = [NSDictionary dictionaryWithGridAbsCoordRange:_commandRange];
    dict[kMarkOutputStart] = [NSDictionary dictionaryWithGridAbsCoord:_outputStart];

    return dict;
}

- (void)addCapturedOutput:(CapturedOutput *)capturedOutput {
    if (!_capturedOutput) {
        _capturedOutput = [[NSMutableArray alloc] init];
    } else if ([self mergeCapturedOutputIfPossible:capturedOutput]) {
        return;
    }
    [_capturedOutput addObject:capturedOutput];
}

- (BOOL)mergeCapturedOutputIfPossible:(CapturedOutput *)capturedOutput {
    CapturedOutput *last = _capturedOutput.lastObject;
    if (![last canMergeFrom:capturedOutput]) {
        return NO;
    }
    [last mergeFrom:capturedOutput];
    return YES;
}

- (void)setCommand:(NSString *)command {
    if (!_command) {
        [self.delegate markDidBecomeCommandMark:self];
    }
    [_command autorelease];
    _command = [command copy];
    self.startDate = [NSDate date];
}

@end

