//
//  Foo.m
//  A fixture. Not real code. // [x release] in a comment must not count.
//

#import "Foo+Private.h"
#import "Bar.h"
#import <objc/runtime.h>
#include <stdatomic.h>
#include "Included.m"

#define DEFINE_GETTER(name) - (int)name { return 1; }
#define PASTE(a, b) a##b
#define LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)

static NSString *const kFooKey = @"FooKey";
static int sCounter;
static NSMutableArray *sCache = nil, *sOther;
static const char *kNames[] = { "a", "b" };
static const FooPoint kPoints[] = { {1, 2}, {3, 4} };
static void FooHelper(int x);
NS_INLINE int FooInline(int y) { return y + sCounter; }

static void FooHelper(int x) {
    sCounter += x;
}

NSString *FooPublicFunction(void) {
    return kFooKey;
}

@interface Foo () {
    char _buffer[16];
    _Atomic int _atomicCount;
}
@end

@implementation Foo {
    NSString *_name;
    NSMutableArray<NSArray<NSString *> *> *_nested;
    FooPoint _point;
    FooPlainEnum _plainEnum;
    FooStrongStruct _strongStruct;
    void (^_completion)(BOOL);
    unsigned int _flag : 1;
    int _doubledStorage, *_pointerValue;
    NSInteger _atomicValue;
    Bar *_bar;
}

@synthesize plain = _plain;

+ (void)load {
    sCache = [[NSMutableArray alloc] init];
}

- (int)doubled {
    return _doubledStorage * 2;
}

- (void)setBar:(Bar *)bar {
    [_bar autorelease];
    _bar = [bar retain];
}

- (Bar *)bar {
    return _bar;
}

- (void)increment {
    _doubledStorage = _doubledStorage + 1;
    _point.x = 3;
    FooHelper(1);
    memset(&_buffer, 0, sizeof(_buffer));
    @synchronized (self) {
        _atomicCount++;
    }
}

- (void)reachInto:(Foo *)other {
    NSLog(@"%d", other->_doubledStorage);
    self->_flag = 1;
}

- (void)dynamic:(NSString *)selName {
    [self performSelector:NSSelectorFromString(selName)];
    NSLog(@"%@", NSStringFromSelector(_cmd));
    Class c = NSClassFromString(@"Bar");
    method_exchangeImplementations(NULL, NULL);
    @try {
        [[[NSObject alloc] init] autorelease];
    } @catch (NSException *e) {
    }
    NSLog(@"a string with performSelector: in it");
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
}

- (void)dealloc {
    [_name release];
    [super dealloc];
}

@end
