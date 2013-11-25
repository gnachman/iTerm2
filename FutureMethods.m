//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"

const int FutureNSWindowCollectionBehaviorStationary = (1 << 4);  // value stolen from 10.6 SDK

static FutureNSScrollerStyle GetScrollerStyle(id theObj)
{
    NSMethodSignature *sig = [[NSScroller class] instanceMethodSignatureForSelector:@selector(scrollerStyle)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:theObj];
    [inv setSelector:@selector(scrollerStyle)];
    [inv invoke];
    FutureNSScrollerStyle result;
    [inv getReturnValue:&result];
    return result;
}

@implementation NSScroller (Future)

- (FutureNSScrollerStyle)futureScrollerStyle
{
    if ([self respondsToSelector:@selector(scrollerStyle)]) {
        return GetScrollerStyle(self);
    } else {
        return FutureNSScrollerStyleLegacy;
    }
}

@end

@implementation NSScrollView (Future)

- (FutureNSScrollerStyle)futureScrollerStyle
{
    if ([self respondsToSelector:@selector(scrollerStyle)]) {
        return GetScrollerStyle(self);
    } else {
        return FutureNSScrollerStyleLegacy;
    }
}

@end

@implementation CIImage (Future)


@end

@implementation NSObject (Future)

- (BOOL)performSelectorReturningBool:(SEL)selector withObjects:(NSArray *)objects {
    NSMethodSignature *mySignature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:mySignature];
    [myInvocation setTarget:self];
    [myInvocation setSelector:selector];
    if (objects.count > 0) {
        void *pointers[objects.count];
        for (int i = 0; i < objects.count; i++) {
            pointers[i] = [objects objectAtIndex:i];
            [myInvocation setArgument:&pointers[i]  // pointer to object
                              atIndex:i];
        }
    }
    [myInvocation invoke];
    BOOL result;
    [myInvocation getReturnValue:&result];
    return result;
}

- (BOOL)performSelectorReturningCGFloat:(SEL)selector withObjects:(NSArray *)objects {
    NSMethodSignature *mySignature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:mySignature];
    [myInvocation setTarget:self];
    [myInvocation setSelector:selector];
    if (objects.count > 0) {
        void *pointers[objects.count];
        for (int i = 0; i < objects.count; i++) {
            pointers[i] = [objects objectAtIndex:i];
            [myInvocation setArgument:&pointers[i]  // pointer to object
                              atIndex:i];
        }
    }
    [myInvocation invoke];
    CGFloat result;
    [myInvocation getReturnValue:&result];
    return result;
}

- (void)performSelector:(SEL)selector takingNSInteger:(NSInteger)arg {
    NSMethodSignature *mySignature = [[self class] instanceMethodSignatureForSelector:selector];
    NSInvocation *myInvocation = [NSInvocation invocationWithMethodSignature:mySignature];
    [myInvocation setTarget:self];
    [myInvocation setSelector:selector];
    [myInvocation setArgument:&arg
                      atIndex:2];
    [myInvocation invoke];
}

@end

@implementation NSScroller (future)

- (void)futureSetKnobStyle:(NSInteger)newKnobStyle {
    if ([self respondsToSelector:@selector(setKnobStyle:)]) {
        [self performSelector:@selector(setKnobStyle:) takingNSInteger:newKnobStyle];
    }
}

@end

@implementation NSScreen (future)

- (CGFloat)futureBackingScaleFactor {
    if ([self respondsToSelector:@selector(backingScaleFactor)]) {
        return [self performSelectorReturningCGFloat:@selector(backingScaleFactor) withObjects:nil];
    } else {
        return 1.0;
    }
}

@end

static void *GetFunctionByName(NSString *library, char *func) {
    CFBundleRef bundle;
    CFURLRef bundleURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef) library, kCFURLPOSIXPathStyle, true);
    CFStringRef functionName = CFStringCreateWithCString(kCFAllocatorDefault, func, kCFStringEncodingASCII);
    bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
    void *f = NULL;
    if (bundle) {
        f = CFBundleGetFunctionPointerForName(bundle, functionName);
        CFRelease(bundle);
    }
    CFRelease(functionName);
    CFRelease(bundleURL);
    return f;
}

CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void) {
    static BOOL tried = NO;
    static CGSSetWindowBackgroundBlurRadiusFunction *function = NULL;
    if (!tried) {
        function  = GetFunctionByName(@"/System/Library/Frameworks/ApplicationServices.framework",
                                      "CGSSetWindowBackgroundBlurRadius");
        tried = YES;
    }
    return function;
}

CTFontDrawGlyphsFunction* GetCTFontDrawGlyphsFunction(void) {
    static BOOL tried = NO;
    static CTFontDrawGlyphsFunction *function = NULL;
    if (!tried) {
        // This works in 10.8
        function  = GetFunctionByName(@"/System/Library/Frameworks/CoreText.framework",
                                      "CTFontDrawGlyphs");
        if (!function) {
            // This works in 10.7 and earlier versions won't have it.
            function = GetFunctionByName(@"/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreText.framework",
                                         "CTFontDrawGlyphs");
        }
        tried = YES;
    }
    return function;
}

