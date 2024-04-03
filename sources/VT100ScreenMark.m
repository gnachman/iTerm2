//
//  VT100ScreenMark.m
//  iTerm
//
//  Created by George Nachman on 12/5/13.
//
//

#import "VT100ScreenMark.h"
#import "CapturedOutput.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSStringITerm.h"
#import "ScreenCharArray.h"
#import "iTermPromise.h"

static NSString *const kScreenMarkIsPrompt = @"Is Prompt";
static NSString *const kMarkGuidKey = @"Guid";
static NSString *const kMarkCapturedOutputKey = @"Captured Output";
static NSString *const kMarkCommandKey = @"Command";
static NSString *const kMarkCodeKey = @"Code";
static NSString *const kMarkPromptDetectedByTrigger = @"Prompt Detected by Trigger";
static NSString *const kMarkLineStyleKey = @"Line Style";
static NSString *const kMarkHasCode = @"Has Code";
static NSString *const kMarkStartDateKey = @"Start Date";
static NSString *const kMarkEndDateKey = @"End Date";
static NSString *const kMarkNameKey = @"Name";
static NSString *const kMarkSessionGuidKey = @"Session Guid";
static NSString *const kMarkPromptRange = @"Prompt Range";
static NSString *const kMarkPromptText = @"Prompt Text";
static NSString *const kMarkCommandRange = @"Command Range";
static NSString *const kMarkOutputStart = @"Output Start";

@implementation VT100ScreenMark {
    NSMutableArray<CapturedOutput *> *_capturedOutput;
    iTermPromise<NSNumber *> *_returnCodePromise;
    id<iTermPromiseSeal> _codeSeal;
}

@synthesize isPrompt = _isPrompt;
@synthesize guid = _guid;
@synthesize clearCount = _clearCount;
@synthesize capturedOutput = _capturedOutput;
@synthesize code = _code;
@synthesize promptDetectedByTrigger = _promptDetectedByTrigger;
@synthesize lineStyle = _lineStyle;
@synthesize hasCode = _hasCode;
@synthesize command = _command;
@synthesize startDate = _startDate;
@synthesize name = _name;
@synthesize endDate = _endDate;
@synthesize sessionGuid = _sessionGuid;
@synthesize promptRange = _promptRange;
@synthesize promptText = _promptText;
@synthesize commandRange = _commandRange;
@synthesize outputStart = _outputStart;

+ (NSMapTable *)registry {
    static NSMapTable *registry;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality)
                                             valueOptions:(NSPointerFunctionsWeakMemory | NSPointerFunctionsOpaquePersonality)
                                                 capacity:1024];
    });
    return registry;
}

+ (id<VT100ScreenMarkReading>)markWithGuid:(NSString *)guid
                         forMutationThread:(BOOL)forMutationThread {
    @synchronized([VT100ScreenMark class]) {
        VT100ScreenMark *mark = [self.registry objectForKey:guid];
        if (forMutationThread) {
            return mark;
        }
        return [mark doppelganger];
    }
}

- (instancetype)init {
    return [self initRegistered:YES];
}

- (instancetype)initRegistered:(BOOL)shouldRegister {
    self = [super init];
    if (self) {
        if (shouldRegister) {
            @synchronized([VT100ScreenMark class]) {
                [[self.class registry] setObject:self forKey:self.guid];
            }
        }
        _promptRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _commandRange = VT100GridAbsCoordRangeMake(-1, -1, -1, -1);
        _outputStart = VT100GridAbsCoordMake(-1, -1);
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return [self initWithDictionary:dict shouldRegister:YES];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict shouldRegister:(BOOL)shouldRegister {
    self = [super initWithDictionary:dict];
    if (self) {
        _code = [dict[kMarkCodeKey] intValue];
        _promptDetectedByTrigger = [dict[kMarkPromptDetectedByTrigger] boolValue];
        _lineStyle = [dict[kMarkLineStyleKey] boolValue];
        _hasCode = [dict[kMarkHasCode] boolValue];
        if (_code && !_hasCode) {
            // Not so great way of migrating old marks. Misses those with a value of 0 :(
            _hasCode = YES;
        }
        _isPrompt = [dict[kScreenMarkIsPrompt] boolValue];
        if ([dict[kMarkGuidKey] isKindOfClass:[NSString class]]) {
            _guid = [dict[kMarkGuidKey] copy];
        } else {
            _guid = [NSString uuid];
        }
        _sessionGuid = [dict[kMarkSessionGuidKey] copy];
        NSTimeInterval start = [dict[kMarkStartDateKey] doubleValue];
        if (start > 0) {
            _startDate = [NSDate dateWithTimeIntervalSinceReferenceDate:start];
        }
        NSTimeInterval end = [dict[kMarkEndDateKey] doubleValue];
        if (end > 0) {
            _endDate = [NSDate dateWithTimeIntervalSinceReferenceDate:end];
        }
        _name = [dict[kMarkNameKey] copy];
        NSMutableArray *array = [NSMutableArray array];
        _capturedOutput = array;
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
        if (dict[kMarkPromptText]) {
            NSArray<NSDictionary *> *dicts = dict[kMarkPromptText];
            _promptText = [dicts mapWithBlock:^id _Nullable(NSDictionary * _Nonnull dict) {
                return [[ScreenCharArray alloc] initWithDictionary:dict];
            }];
        } else {
            _promptText = nil;
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
        if (shouldRegister) {
            @synchronized([VT100ScreenMark class]) {
                [[self.class registry] setObject:self forKey:self.guid];
            }
        }
    }
    return self;
}

// Note that this assumes the copy will be a doppelganger (since it uses CapturedOutput doppelgangers).
- (instancetype)copyWithZone:(NSZone *)zone {
    assert(!self.isDoppelganger);

    // Doppelgangers should not be registered. They take the GUID of the progenitor.
    VT100ScreenMark *mark = [[VT100ScreenMark alloc] initRegistered:NO];

    mark->_code = _code;
    mark->_promptDetectedByTrigger = _promptDetectedByTrigger;
    mark->_lineStyle = _lineStyle;
    mark->_hasCode = _hasCode;
    mark->_isPrompt = _isPrompt;
    mark->_guid = [_guid copy];
    mark->_sessionGuid = [_sessionGuid copy];
    mark->_startDate = _startDate;
    mark->_name = [_name copy];
    mark->_endDate = _endDate;
    mark->_capturedOutput = [[_capturedOutput mapWithBlock:^id(CapturedOutput *capturedOutput) {
        return [capturedOutput doppelganger];
    }] mutableCopy];
    mark->_command = [_command copy];
    mark->_promptRange = _promptRange;
    mark->_promptText = [_promptText copy];
    mark->_commandRange = _commandRange;
    mark->_outputStart = _outputStart;

    return mark;
}

- (void)dealloc {
    @synchronized([VT100ScreenMark class]) {
        // I think this is not needed because we use weak pointers but I also don't trust
        // NSMapTable to ever remove dead objects. Do this to avoid a possible waste of memory.
        [[self.class registry] removeObjectForKey:_guid];
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p guid=%@ name=%@ command=%@ %@>",
            NSStringFromClass([self class]),
            self,
            _guid,
            _name,
            _command,
            self.isDoppelganger ? @"IsDop" : @"NotDop"];
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
    NSMutableDictionary *dict = [[super dictionaryValue] mutableCopy];
    dict[kScreenMarkIsPrompt] = @(_isPrompt);
    dict[kMarkGuidKey] = self.guid;
    dict[kMarkCapturedOutputKey] = [self capturedOutputDictionaries];
    dict[kMarkHasCode] = @(_hasCode);
    dict[kMarkCodeKey] = @(_code);
    dict[kMarkPromptDetectedByTrigger] = @(_promptDetectedByTrigger);
    dict[kMarkLineStyleKey] = @(_lineStyle);
    dict[kMarkCommandKey] = _command ?: [NSNull null];
    dict[kMarkStartDateKey] = @([self.startDate timeIntervalSinceReferenceDate]);
    if (_name) {
        dict[kMarkNameKey] = _name;
    }
    dict[kMarkEndDateKey] = @([self.endDate timeIntervalSinceReferenceDate]);
    dict[kMarkSessionGuidKey] = self.sessionGuid ?: [NSNull null];
    dict[kMarkPromptRange] = [NSDictionary dictionaryWithGridAbsCoordRange:_promptRange];
    dict[kMarkPromptText] = [_promptText mapWithBlock:^id _Nullable(ScreenCharArray *sca) {
        return sca.dictionaryValue;
    }];
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
    _command = [command copy];
    self.startDate = [NSDate date];
}

- (void)setCode:(int)code {
    _code = code;
    _hasCode = YES;
    [_codeSeal fulfill:@(code)];
    _codeSeal = nil;
}

- (void)incrementClearCount {
    _clearCount += 1;
}

- (id<VT100ScreenMarkReading>)doppelganger {
    return (id<VT100ScreenMarkReading>)[super doppelganger];
}

- (NSString *)shortDebugDescription {
    return [NSString stringWithFormat:@"[ScreenMark prompt=%@ code=%@ cmd=%@]",
            @(_isPrompt), @(_code), _command];
}


- (iTermPromise<NSNumber *> *)returnCodePromise {
    if (!_returnCodePromise) {
        _returnCodePromise = [iTermPromise promise:^(id<iTermPromiseSeal>  _Nonnull seal) {
            _codeSeal = seal;
        }];
    }
    return _returnCodePromise;
}

- (BOOL)isRunning {
    return _command.length > 0 && _endDate == nil;
}

@end
