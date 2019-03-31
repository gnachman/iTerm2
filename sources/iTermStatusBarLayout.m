//
//  iTermStatusBarLayout.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarLayout.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSColor+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

static NSString *const iTermStatusBarLayoutDictionaryKeySeparatorColor = @"separator color 2";  // "separator color" is deprecated after 3.0.0beta1
static NSString *const iTermStatusBarLayoutDictionaryKeyBackgroundColor = @"background color";
static NSString *const iTermStatusBarLayoutDictionaryKeyDefaultTextColor = @"default text color";
static NSString *const iTermStatusBarLayoutDictionaryKeyAlgorithm = @"algorithm";
static NSString *const iTermStatusBarLayoutDictionaryKeyFont = @"font";

NSString *const iTermStatusBarLayoutKeyComponents = @"components";
NSString *const iTermStatusBarLayoutKeyAdvancedConfiguration = @"advanced configuration";
// NOTE: If you add keys you might also need to update the computed default value in iTermProfilePreferences

static NSString *const iTermStatusBarLayoutKeyConfiguration = @"configuration";
static NSString *const iTermStatusBarLayoutKeyClass = @"class";

@implementation iTermStatusBarAdvancedConfiguration

+ (NSFont *)defaultFont {
    return [NSFont systemFontOfSize:12];
}

+ (instancetype)advancedConfigurationFromDictionary:(NSDictionary *)dict {
    iTermStatusBarAdvancedConfiguration *configuration = [[iTermStatusBarAdvancedConfiguration alloc] init];
    configuration.separatorColor = [dict[iTermStatusBarLayoutDictionaryKeySeparatorColor] colorValue];
    configuration.backgroundColor = [dict[iTermStatusBarLayoutDictionaryKeyBackgroundColor] colorValue];
    configuration.defaultTextColor = [dict[iTermStatusBarLayoutDictionaryKeyDefaultTextColor] colorValue];
    configuration.layoutAlgorithm = [dict[iTermStatusBarLayoutDictionaryKeyAlgorithm] unsignedIntegerValue];
    configuration.font = [dict[iTermStatusBarLayoutDictionaryKeyFont] fontValue];

    return configuration;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        self.separatorColor = [[aDecoder decodeObjectOfClass:[NSDictionary class] forKey:iTermStatusBarLayoutDictionaryKeySeparatorColor] colorValue];
        self.backgroundColor = [[aDecoder decodeObjectOfClass:[NSDictionary class] forKey:iTermStatusBarLayoutDictionaryKeyBackgroundColor] colorValue];
        self.defaultTextColor = [[aDecoder decodeObjectOfClass:[NSDictionary class] forKey:iTermStatusBarLayoutDictionaryKeyDefaultTextColor] colorValue];
        self.layoutAlgorithm = [aDecoder decodeIntegerForKey:iTermStatusBarLayoutDictionaryKeyAlgorithm];
        self.font = [[aDecoder decodeObjectOfClass:[NSString class] forKey:iTermStatusBarLayoutDictionaryKeyFont] fontValue];
    }
    return self;
}

- (NSDictionary *)dictionaryValue {
    NSDictionary *dict = @{ iTermStatusBarLayoutDictionaryKeySeparatorColor: [self.separatorColor dictionaryValue] ?: [NSNull null],
                            iTermStatusBarLayoutDictionaryKeyBackgroundColor: [self.backgroundColor dictionaryValue] ?: [NSNull null],
                            iTermStatusBarLayoutDictionaryKeyDefaultTextColor: [self.defaultTextColor dictionaryValue] ?: [NSNull null],
                            iTermStatusBarLayoutDictionaryKeyAlgorithm: @(self.layoutAlgorithm),
                            iTermStatusBarLayoutDictionaryKeyFont: [self.font stringValue] ?: [NSNull null] };
    return [dict dictionaryByRemovingNullValues];
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:[self.separatorColor dictionaryValue] forKey:iTermStatusBarLayoutDictionaryKeySeparatorColor];
    [aCoder encodeObject:[self.backgroundColor dictionaryValue] forKey:iTermStatusBarLayoutDictionaryKeyBackgroundColor];
    [aCoder encodeObject:[self.defaultTextColor dictionaryValue] forKey:iTermStatusBarLayoutDictionaryKeyDefaultTextColor];
    [aCoder encodeInteger:self.layoutAlgorithm forKey:iTermStatusBarLayoutDictionaryKeyAlgorithm];
    [aCoder encodeObject:[self.font stringValue] forKey:iTermStatusBarLayoutDictionaryKeyFont];
}

@end

@implementation iTermStatusBarLayout {
    NSMutableArray<id<iTermStatusBarComponent>> *_components;
}

+ (NSArray<id<iTermStatusBarComponent>> *)componentsArrayFromDictionary:(NSDictionary *)dictionary
                                                                  scope:(iTermVariableScope *)scope {
    NSMutableArray<id<iTermStatusBarComponent>> *result = [NSMutableArray array];
    for (NSDictionary *dict in dictionary[iTermStatusBarLayoutKeyComponents]) {
        NSString *className = dict[iTermStatusBarLayoutKeyClass];
        Class theClass = NSClassFromString(className);
        if (![theClass conformsToProtocol:@protocol(iTermStatusBarComponent)]) {
            DLog(@"Bogus class %@", theClass);
            continue;
        }
        NSDictionary *configuration = dict[iTermStatusBarLayoutKeyConfiguration];
        if (!configuration) {
            DLog(@"Missing configuration for %@", dict);
            continue;
        }
        configuration = [configuration dictionaryBySettingObject:dictionary[iTermStatusBarLayoutKeyAdvancedConfiguration] ?: @{}
                                                          forKey:iTermStatusBarComponentConfigurationKeyLayoutAdvancedConfigurationDictionaryValue];
        id<iTermStatusBarComponent> component = [[theClass alloc] initWithConfiguration:configuration
                                                                                  scope:scope];
        [result addObject:component];
    }
    return result;
}

- (instancetype)initWithDictionary:(NSDictionary *)layout
                             scope:(nullable iTermVariableScope *)scope {
    return [self initWithComponents:[iTermStatusBarLayout componentsArrayFromDictionary:layout
                                                                                  scope:scope]
                      advancedConfiguration:[iTermStatusBarAdvancedConfiguration advancedConfigurationFromDictionary:layout[iTermStatusBarLayoutKeyAdvancedConfiguration]]];
}

- (instancetype)initWithComponents:(NSArray<iTermStatusBarComponent> *)components
             advancedConfiguration:(iTermStatusBarAdvancedConfiguration *)advancedConfiguration {
    self = [super init];
    if (self) {
        _advancedConfiguration = advancedConfiguration;
        _components = [components mutableCopy];
    }
    return self;
}

- (instancetype)initWithScope:(nullable iTermVariableScope *)scope {
    return [self initWithDictionary:@{} scope:scope];
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    return [self initWithComponents:[aDecoder decodeObjectOfClass:[NSArray class] forKey:@"components"]
              advancedConfiguration:[aDecoder decodeObjectOfClass:[iTermStatusBarAdvancedConfiguration class] forKey:@"advanced configuration"]];
}

- (void)setComponents:(NSArray<id<iTermStatusBarComponent>> *)components {
    _components = [components copy];
    [self.delegate statusBarLayoutDidChange:self];
}

- (NSArray *)arrayValue {
    return [_components mapWithBlock:^id(id<iTermStatusBarComponent> component) {
        return @{ iTermStatusBarLayoutKeyClass: NSStringFromClass([component class]),
                  iTermStatusBarLayoutKeyConfiguration: component.configuration };
    }];
}

- (NSDictionary *)dictionaryValue {
    return [@{ iTermStatusBarLayoutKeyComponents: [self arrayValue],
               iTermStatusBarLayoutKeyAdvancedConfiguration: [_advancedConfiguration dictionaryValue] ?: [NSNull null] } dictionaryByRemovingNullValues];
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_components forKey:@"components"];
    [aCoder encodeObject:_advancedConfiguration forKey:@"advanced configuration"];
}

@end

NS_ASSUME_NONNULL_END
