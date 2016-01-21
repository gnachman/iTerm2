//
//  OCHamcrest - HCHasProperty.m
//  Copyright 2013 hamcrest.org. See LICENSE.txt
//
//  Created by: Justin Shacklette
//

#import "HCHasProperty.h"

#import "HCDescription.h"
#import "HCRequireNonNilObject.h"
#import "HCWrapInMatcher.h"


@implementation HCHasProperty

+ (id)hasProperty:(NSString *)property value:(id<HCMatcher>)aValueMatcher
{
    return [[self alloc] initWithProperty:property value:aValueMatcher];
}

- (id)initWithProperty:(NSString *)property value:(id<HCMatcher>)aValueMatcher
{
    HCRequireNonNilObject(property);

    self = [super init];
    if (self != nil)
    {
        propertyName = [property copy];
        valueMatcher = aValueMatcher;
    }
    return self;
}

- (BOOL)matches:(id)item
{
    SEL propertyGetter = NSSelectorFromString(propertyName);
    if (![item respondsToSelector:propertyGetter])
        return NO;

    id propertyValue = [self objectFromInvokingSelector:propertyGetter onObject:item];
    return [valueMatcher matches:propertyValue];
}

- (id)objectFromInvokingSelector:(SEL)selector onObject:(id)object
{
    NSMethodSignature *getterSignature = [object methodSignatureForSelector:selector];
    NSInvocation *getterInvocation = [NSInvocation invocationWithMethodSignature:getterSignature];
    [getterInvocation setTarget:object];
    [getterInvocation setSelector:selector];
    [getterInvocation invoke];

    __unsafe_unretained id result = nil;
    const char *argType = [getterSignature methodReturnType];
    if (strncmp(argType, @encode(char), 1) == 0)
    {
        char charValue;
        [getterInvocation getReturnValue:&charValue];
        result = @(charValue);
    }
    else if (strncmp(argType, @encode(int), 1) == 0)
    {
        int intValue;
        [getterInvocation getReturnValue:&intValue];
        result = @(intValue);
    }
    else if (strncmp(argType, @encode(short), 1) == 0)
    {
        short shortValue;
        [getterInvocation getReturnValue:&shortValue];
        result = @(shortValue);
    }
    else if (strncmp(argType, @encode(long), 1) == 0)
    {
        long longValue;
        [getterInvocation getReturnValue:&longValue];
        result = @(longValue);
    }
    else if (strncmp(argType, @encode(long long), 1) == 0)
    {
        long long longLongValue;
        [getterInvocation getReturnValue:&longLongValue];
        result = @(longLongValue);
    }
    else if (strncmp(argType, @encode(unsigned char), 1) == 0)
    {
        unsigned char unsignedCharValue;
        [getterInvocation getReturnValue:&unsignedCharValue];
        result = @(unsignedCharValue);
    }
    else if (strncmp(argType, @encode(unsigned int), 1) == 0)
    {
        unsigned int unsignedIntValue;
        [getterInvocation getReturnValue:&unsignedIntValue];
        result = @(unsignedIntValue);
    }
    else if (strncmp(argType, @encode(unsigned short), 1) == 0)
    {
        unsigned short unsignedShortValue;
        [getterInvocation getReturnValue:&unsignedShortValue];
        result = @(unsignedShortValue);
    }
    else if (strncmp(argType, @encode(unsigned long), 1) == 0)
    {
        unsigned long unsignedLongValue;
        [getterInvocation getReturnValue:&unsignedLongValue];
        result = @(unsignedLongValue);
    }
    else if (strncmp(argType, @encode(unsigned long long), 1) == 0)
    {
        unsigned long long unsignedLongLongValue;
        [getterInvocation getReturnValue:&unsignedLongLongValue];
        result = @(unsignedLongLongValue);
    }
    else if (strncmp(argType, @encode(float), 1) == 0)
    {
        float floatValue;
        [getterInvocation getReturnValue:&floatValue];
        result = @(floatValue);
    }
    else if (strncmp(argType, @encode(double), 1) == 0)
    {
        double doubleValue;
        [getterInvocation getReturnValue:&doubleValue];
        result = @(doubleValue);
    }
    else if (strncmp(argType, @encode(id), 1) == 0)
    {
        [getterInvocation getReturnValue:&result];
    }

    return result;
}

- (void)describeTo:(id<HCDescription>)description
{
    [[[[description appendText:@"an object with "]
                    appendText:propertyName]
                    appendText:@" "]
                    appendDescriptionOf:valueMatcher];
}
@end


#pragma mark -

id<HCMatcher> HC_hasProperty(NSString *name, id valueMatch)
{
    return [HCHasProperty hasProperty:name value:HCWrapInMatcher(valueMatch)];
}
