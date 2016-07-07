//
//  iTermScriptingWindow.m
//  iTerm2
//
//  Created by George Nachman on 7/6/16.
//
//

#import "iTermScriptingWindow.h"

@implementation iTermScriptingWindow

+ (instancetype)scriptingWindowWithWindow:(NSWindow *)window {
    return [[[self alloc] initWithObject:window] autorelease];
}

- (instancetype)initWithObject:(NSWindow *)window {
    self = [super init];
    if (self) {
        _underlyingWindow = [window retain];
    }
    return self;
}

- (void)dealloc {
    [_underlyingWindow release];
    [super dealloc];
}

#pragma mark - NSProxy

- (Class)class {
    return [iTermScriptingWindow class];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    return [_underlyingWindow methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:_underlyingWindow];
}

// I did my best to find all the relevant NSObject categories that could be
// invoked by scripting and manually forward them. They don't use
// forwardInvocation: because they have an implementation in this object
// already by virtue of the category's existence. As more pop up, add them
// here. This is pretty much the perfect storm of too much dynamic stuff making
// it impossible to write correct code.

- (id)objectSpecifier {
    return [_underlyingWindow objectSpecifier];
}

- (id)valueForKey:(NSString *)key {
    return [_underlyingWindow valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key {
    [_underlyingWindow setValue:value forKey:key];
}

- (id)valueForKeyPath:(NSString *)keyPath {
    return [_underlyingWindow valueForKeyPath:keyPath];
}

- (id)valueForUndefinedKey:(NSString *)key {
    return [_underlyingWindow valueForUndefinedKey:key];
}

- (NSArray<NSString *> *)exposedBindings {
    return [_underlyingWindow exposedBindings];
}

- (Class)valueClassForBinding:(NSString *)binding {
    return [_underlyingWindow valueClassForBinding:binding];
}

- (void)bind:(NSString *)binding toObject:(id)observable withKeyPath:(NSString *)keyPath options:(NSDictionary<NSString *,id> *)options {
    [_underlyingWindow bind:binding toObject:observable withKeyPath:keyPath options:options];
}

- (void)unbind:(NSString *)binding {
    [_underlyingWindow unbind:binding];
}

- (NSDictionary<NSString *,id> *)infoForBinding:(NSString *)binding {
    return [_underlyingWindow infoForBinding:binding];
}

- (NSArray<NSAttributeDescription *> *)optionDescriptionsForBinding:(NSString *)aBinding {
    return [_underlyingWindow optionDescriptionsForBinding:aBinding];
}

@end
