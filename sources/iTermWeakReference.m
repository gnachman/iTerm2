//
//  iTermWeakReference.m
//  iTerm2
//
//  Created by George Nachman on 2/6/16.
//
//

#import "iTermWeakReference.h"

#import "DebugLogging.h"

#import <objc/runtime.h>

@interface iTermWeakReference()
- (void)nullify;
@end

@interface iTermDeallocReporterObject : NSObject
@property(nonatomic, assign) iTermWeakReference *owner;
@end

@implementation iTermDeallocReporterObject

- (void)dealloc {
    DLog(@"Reporter dealloced");
    assert([NSThread isMainThread]);
    [_owner nullify];
    [super dealloc];
}

@end

@implementation iTermWeakReference {
    iTermDeallocReporterObject *_reporter;
}

+ (instancetype)weakReferenceToObject:(id)object {
    return [[[self alloc] initWithObject:object] autorelease];
}

- (instancetype)initWithObject:(id)object {
    self = [super init];
    if (self) {
        _object = object;
        _reporter = [[iTermDeallocReporterObject alloc] init];
        _reporter.owner = self;
        objc_setAssociatedObject(object,
                                 [self class],
                                 _reporter,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_reporter release];
    }
    return self;
}

- (void)dealloc {
    assert([NSThread isMainThread]);
    if (_object) {
        _reporter.owner = nil;
        objc_setAssociatedObject(nil, [self class], nil, OBJC_ASSOCIATION_ASSIGN);
    }
    [super dealloc];
}

- (void)nullify {
    DLog(@"Nullify %@ from %@", _object, [NSThread callStackSymbols]);
    _reporter = nil;
    _object = nil;
}

@end
