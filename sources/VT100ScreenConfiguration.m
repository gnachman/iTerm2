//
//  VT100ScreenConfiguration.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/21/21.
//

#import "VT100ScreenConfiguration.h"
#import "NSArray+iTerm.h"

@interface VT100ScreenConfiguration()
@property (nonatomic, readwrite) BOOL shouldPlacePromptAtFirstColumn;
@property (nonatomic, copy, readwrite) NSString *sessionGuid;
@property (nonatomic, readwrite) BOOL treatAmbiguousCharsAsDoubleWidth;
@property (nonatomic, readwrite) NSInteger unicodeVersion;
@property (nonatomic, readwrite) BOOL enableTriggersInInteractiveApps;
@property (nonatomic, readwrite) BOOL triggerParametersUseInterpolatedStrings;
@property (nonatomic, copy, readwrite) NSArray<NSDictionary *> *triggerProfileDicts;
@property (nonatomic, readwrite) BOOL notifyOfAppend;
@property (nonatomic, readwrite) BOOL isTmuxClient;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *reportableVariables;

@property (nonatomic, readwrite) BOOL isDirty;
@end

@implementation VT100ScreenConfiguration

@synthesize shouldPlacePromptAtFirstColumn = _shouldPlacePromptAtFirstColumn;
@synthesize sessionGuid = _sessionGuid;
@synthesize treatAmbiguousCharsAsDoubleWidth = _treatAmbiguousCharsAsDoubleWidth;
@synthesize unicodeVersion = _unicodeVersion;
@synthesize enableTriggersInInteractiveApps = _enableTriggersInInteractiveApps;
@synthesize triggerParametersUseInterpolatedStrings = _triggerParametersUseInterpolatedStrings;
@synthesize triggerProfileDicts = _triggerProfileDicts;
@synthesize notifyOfAppend = _notifyOfAppend;
@synthesize isTmuxClient = _isTmuxClient;
@synthesize reportableVariables = _reportableVariables;

@synthesize isDirty = _isDirty;

- (instancetype)initFrom:(VT100ScreenConfiguration *)other {
    self = [super init];
    if (self) {
        _shouldPlacePromptAtFirstColumn = other.shouldPlacePromptAtFirstColumn;
        _sessionGuid = other.sessionGuid;
        _treatAmbiguousCharsAsDoubleWidth = other.treatAmbiguousCharsAsDoubleWidth;
        _unicodeVersion = other.unicodeVersion;
        _enableTriggersInInteractiveApps = other.enableTriggersInInteractiveApps;
        _triggerParametersUseInterpolatedStrings = other.triggerParametersUseInterpolatedStrings;
        _triggerProfileDicts = [other.triggerProfileDicts copy];
        _notifyOfAppend = other.notifyOfAppend;
        _isTmuxClient = other.isTmuxClient;
        _reportableVariables = [other.reportableVariables copy];

        _isDirty = other.isDirty;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return self;
}

- (NSString *)description {
    NSDictionary *dict = @{ @"shouldPlacePromptAtFirstColumn": @(_shouldPlacePromptAtFirstColumn),
                            @"sessionGuid": _sessionGuid ?: @"(nil)",
                            @"treatAmbiguousCharsAsDoubleWidth": @(_treatAmbiguousCharsAsDoubleWidth),
                            @"unicodeVersion": @(_unicodeVersion),
                            @"enableTriggersInInteractiveApps": @(_enableTriggersInInteractiveApps),
                            @"triggerParametersUseInterpolatedStrings": @(_triggerParametersUseInterpolatedStrings),
                            @"triggerProfileDicts (count)": @(_triggerProfileDicts.count),
                            @"notifyOfAppend": @(_notifyOfAppend),
                            @"isTmuxClient": @(_isTmuxClient),
                            @"reportableVariables (count)": @(_reportableVariables.count),

                            @"isDirty": @(_isDirty),
    };
    NSArray<NSString *> *keys = [dict.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *kvps = [keys mapWithBlock:^id(NSString *key) {
        return [NSString stringWithFormat:@"    %@=%@", key, dict[key]];
    }];
    NSString *values = [kvps componentsJoinedByString:@"\n"];
    return [NSString stringWithFormat:@"<%@: %p\n%@>", NSStringFromClass([self class]), self, values];
}
@end

@implementation VT100MutableScreenConfiguration

@dynamic shouldPlacePromptAtFirstColumn;
@dynamic sessionGuid;
@dynamic treatAmbiguousCharsAsDoubleWidth;
@dynamic unicodeVersion;
@dynamic enableTriggersInInteractiveApps;
@dynamic triggerParametersUseInterpolatedStrings;
@dynamic triggerProfileDicts;
@dynamic notifyOfAppend;
@dynamic isTmuxClient;
@dynamic reportableVariables;

@dynamic isDirty;

- (id)copyWithZone:(NSZone *)zone {
    return [[VT100ScreenConfiguration alloc] initFrom:self];
}

@end

