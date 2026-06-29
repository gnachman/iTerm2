//
//  iTermVariablesIndex.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/17/19.
//

#import "iTermVariablesIndex.h"

#import "iTermVariables.h"

@implementation iTermVariablesIndex {
    NSMapTable<NSString *, iTermVariables *> *_dict;
}

+ (instancetype)sharedInstance {
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSPointerFunctionsOptions weakOptions = (NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPersonality);
        NSPointerFunctionsOptions strongOptions = (NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality);
        _dict = [[NSMapTable alloc] initWithKeyOptions:strongOptions
                                          valueOptions:weakOptions
                                              capacity:1];
    }
    return self;
}

- (void)removeKey:(NSString *)key {
    [_dict removeObjectForKey:key];
}

- (void)setVariables:(iTermVariables *)variables forKey:(NSString *)key {
    [_dict setObject:variables forKey:key];
}

- (nullable iTermVariables *)variablesForKey:(NSString *)key {
    return [_dict objectForKey:key];
}

@end
