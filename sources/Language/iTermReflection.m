//
//  iTermReflection.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/18/19.
//

#import "iTermReflection.h"

#import "NSArray+iTerm.h"

#import <objc/runtime.h>

@implementation iTermReflectionMethodArgument

- (instancetype)initWithObjectHavingClassName:(NSString *)className
                                 argumentName:(NSString *)argumentName {
    self = [super init];
    if (self) {
        _argumentName = argumentName.copy;
        _type = iTermReflectionMethodArgumentTypeObject;
        _className = [className copy];
    }
    return self;
}

- (instancetype)initWithType:(iTermReflectionMethodArgumentType)type
                argumentName:(NSString *)argumentName {
    self = [super init];
    if (self) {
        _argumentName = argumentName.copy;
        _type = type;
    }
    return self;
}

+ (iTermReflectionMethodArgument *)argumentForTypeString:(NSString *)typeString
                                            argumentName:(NSString *)argumentName {
    static dispatch_once_t onceToken;
    static NSDictionary<NSString *, NSNumber *> *simpleTypes;
    dispatch_once(&onceToken, ^{
        simpleTypes = @{ @(@encode(char)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(int)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(short)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(long)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(long)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(long long)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(unsigned char)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(unsigned int)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(unsigned short)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(unsigned long)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(unsigned long long)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(float)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(double)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(_Bool)): @(iTermReflectionMethodArgumentTypeScalar),
                         @(@encode(void)): @(iTermReflectionMethodArgumentTypeVoid),
                         @(@encode(char *)): @(iTermReflectionMethodArgumentTypePointer),
                         @"#": @(iTermReflectionMethodArgumentTypeClass),
                         @":": @(iTermReflectionMethodArgumentTypeSelector),
                         @"?": @(iTermReflectionMethodArgumentTypeUnknown) };
    });

    NSNumber *type = simpleTypes[typeString];
    if (type) {
        return [[iTermReflectionMethodArgument alloc] initWithType:type.unsignedIntegerValue
                                                      argumentName:argumentName];
    }

    if ([typeString hasPrefix:@"@"]) {
        return [self argumentForObjectTypeString:[typeString substringFromIndex:1]
                                    argumentName:argumentName];
    }
    if ([typeString hasPrefix:@"^"]) {
        return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypePointer
                                                      argumentName:argumentName];
    }
    if ([typeString hasPrefix:@"{"]) {
        return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeStruct
                                                      argumentName:argumentName];
    }
    if ([typeString hasPrefix:@"("]) {
        return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeUnion
                                                      argumentName:argumentName];
    }
    if ([typeString hasPrefix:@"b"]) {
        return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeBitField
                                                      argumentName:argumentName];
    }
    if ([typeString hasPrefix:@"["]) {
        return [self argumentForArrayTypeString:[typeString substringWithRange:NSMakeRange(1, typeString.length - 2)]
                                   argumentName:argumentName];
    }
    return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeUnknown
                                                  argumentName:argumentName];
}

+ (iTermReflectionMethodArgument *)argumentForObjectTypeString:(NSString *)typeString
                                                  argumentName:(NSString *)argumentName {
    if ([typeString hasPrefix:@"?"]) {
        return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeBlock
                                                      argumentName:argumentName];
    }
    if (![typeString hasPrefix:@"\""]) {
        // Really, this is an id, but I don't care about non-NSObject objects.
        return [[iTermReflectionMethodArgument alloc] initWithObjectHavingClassName:@"NSObject"
                                                                       argumentName:argumentName];
    }
    NSRange closeQuote = [typeString rangeOfString:@"\"" options:0 range:NSMakeRange(1, typeString.length - 1)];
    assert(closeQuote.location != NSNotFound);
    NSString *className = [typeString substringWithRange:NSMakeRange(1, closeQuote.location - 2)];
    return [[iTermReflectionMethodArgument alloc] initWithObjectHavingClassName:className
                                                                   argumentName:argumentName];
}

+ (iTermReflectionMethodArgument *)argumentForArrayTypeString:(NSString *)typeString
                                                 argumentName:(NSString *)argumentName {
    //iTermReflectionMethodArgument *inner = [self argumentForTypeString:typeString];
    // TODO
    return [[iTermReflectionMethodArgument alloc] initWithType:iTermReflectionMethodArgumentTypeArray
                                                  argumentName:argumentName];
}

@end

@implementation iTermReflection {
    Class _class;
    SEL _selector;
    NSArray<iTermReflectionMethodArgument *> *_arguments;
}

- (instancetype)initWithClass:(Class)theClass
                     selector:(SEL)selector {
    self = [super init];
    if (self) {
        _class = theClass;
        _selector = selector;
    }
    return self;
}

- (NSArray<iTermReflectionMethodArgument *> *)arguments {
    if (!_arguments) {
        _arguments = [self reflectedArguments];
    }
    return _arguments;
}

#pragma mark - Private

- (NSArray<iTermReflectionMethodArgument *> *)reflectedArguments {
    NSMutableArray<iTermReflectionMethodArgument *> *const args = [NSMutableArray array];
    const Method method = class_getInstanceMethod(_class, _selector);
    const unsigned int numberOfArguments = method_getNumberOfArguments(method);
    NSString *const selector = NSStringFromSelector(method_getName(method));
    NSArray<NSString *> *parts = [selector componentsSeparatedByString:@":"];
    if (parts.lastObject.length == 0) {
        parts = [parts arrayByRemovingLastObject];
    }
    assert(parts.count + 2 == numberOfArguments);
    for (NSInteger i = 2; i < numberOfArguments; i++) {
        char buffer[256];
        method_getArgumentType(method,
                               i,
                               buffer,
                               sizeof(buffer));
        iTermReflectionMethodArgument *arg = [iTermReflectionMethodArgument argumentForTypeString:@(buffer)
                                                                                     argumentName:parts[i - 2]];
        [args addObject:arg];
    }
    return args;
}


@end
