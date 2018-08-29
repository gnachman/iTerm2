//
//  iTermStatusBarLayout.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/28/18.
//

#import "iTermStatusBarLayout.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermStatusBarLayoutKeyComponents = @"components";
static NSString *const iTermStatusBarLayoutKeyConfiguration = @"configuration";
static NSString *const iTermStatusBarLayoutKeyClass = @"class";

@implementation iTermStatusBarLayout {
    NSMutableArray<id<iTermStatusBarComponent>> *_components;
}

+ (NSArray<id<iTermStatusBarComponent>> *)componentsArrayFromDictionary:(NSDictionary *)dictionary {
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
        id<iTermStatusBarComponent> component = [[theClass alloc] initWithConfiguration:configuration];
        [result addObject:component];
    }
    return result;
}

- (instancetype)initWithDictionary:(NSDictionary *)layout {
    return [self initWithComponents:[iTermStatusBarLayout componentsArrayFromDictionary:layout]];
}

- (instancetype)initWithComponents:(NSArray<iTermStatusBarComponent> *)components {
    self = [super init];
    if (self) {
        _components = [components mutableCopy];
    }
    return self;
}

- (instancetype)init {
    return [self initWithDictionary:@{}];
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder {
    return [self initWithComponents:[aDecoder decodeObjectOfClass:[NSArray class] forKey:@"components"]];
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
    return @{ iTermStatusBarLayoutKeyComponents: [self arrayValue] };
}


#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_components forKey:@"components"];
}

@end

NS_ASSUME_NONNULL_END
