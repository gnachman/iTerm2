//
//  iTermGlobalScopeController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 2/3/20.
//

#import "iTermGlobalScopeController.h"

#import "iTermObject.h"
#import "iTermPreferences.h"
#import "iTermVariableScope.h"
#import "iTermVariableScope+Global.h"
#import "NSAppearance+iTerm.h"
#import "NSHost+iTerm.h"
#import "NSUserDefaults+iTerm.h"

static char iTermGlobalScopeControllerKVOContext;

@interface iTermGlobalScopeController()<iTermObject>
- (void)themeDidChange;
- (NSString *)effectiveTheme;
@end

NS_CLASS_AVAILABLE_MAC(10_14)
@interface iTermGlobalScopeControllerModernImpl: iTermGlobalScopeController
@end

@implementation iTermGlobalScopeControllerModernImpl

- (instancetype)init {
    self = [super init];
    if (self) {
        [NSApp addObserver:self
                forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))
                   options:NSKeyValueObservingOptionNew
                   context:&iTermGlobalScopeControllerKVOContext];
    }
    return self;
}

- (void)dealloc {
    [NSApp removeObserver:self forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context != &iTermGlobalScopeControllerKVOContext) {
        return;
    }
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(effectiveAppearance))]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self themeDidChange];
        });
    }
}

@end

@implementation iTermGlobalScopeController {
    iTermVariables *_userVariables;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone {
    if (self == [iTermGlobalScopeController class]) {
        return [iTermGlobalScopeControllerModernImpl allocWithZone:zone];
    }
    return [super allocWithZone:zone];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        __weak __typeof(self) weakSelf = self;
        [[NSUserDefaults standardUserDefaults] it_addObserverForKey:kPreferenceKeyTabStyle
                                                              block:^(id _Nonnull newValue) {
                                                                  [weakSelf themeDidChange];
                                                              }];
        [[iTermVariableScope globalsScope] setValue:@(getpid()) forVariableNamed:iTermVariableKeyApplicationPID];
        _userVariables = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone
                                                           owner:self];
        [[iTermVariableScope globalsScope] setValue:_userVariables forVariableNamed:@"user"];
        [[iTermVariableScope globalsScope] setValue:[self effectiveTheme]
                                   forVariableNamed:iTermVariableKeyApplicationEffectiveTheme];
        [[iTermVariableScope globalsScope] setValue:[NSHost fullyQualifiedDomainName]
                                   forVariableNamed:iTermVariableKeyApplicationLocalhostName];
        [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [[iTermVariableScope globalsScope] setValue:[NSHost fullyQualifiedDomainName]
                                       forVariableNamed:iTermVariableKeyApplicationLocalhostName];
        }];
    }
    return self;
}

- (void)themeDidChange {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[iTermVariableScope globalsScope] setValue:[self effectiveTheme]
                                   forVariableNamed:iTermVariableKeyApplicationEffectiveTheme];
    });
}

- (NSString *)effectiveTheme {
    iTermAppearanceOptions options = [NSAppearance it_appearanceOptions];

    NSMutableArray *array = [NSMutableArray array];
    if (options & iTermAppearanceOptionsDark) {
        [array addObject:@"dark"];
    } else {
        [array addObject:@"light"];
    }
    if (options & iTermAppearanceOptionsHighContrast) {
        [array addObject:@"highContrast"];
    }
    if (options & iTermAppearanceOptionsMinimal) {
        [array addObject:@"minimal"];
    }
    return [array componentsJoinedByString:@" "];
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    return nil;
}

- (iTermVariableScope *)objectScope {
    return [iTermVariableScope globalsScope];
}

@end
