//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"
#import "NSSavePanel+iTerm.h"

static NSString *const kApplicationServicesFramework = @"/System/Library/Frameworks/ApplicationServices.framework";
static NSString *const kMultitouchSupportFramework =  @"/System/Library/PrivateFrameworks/MultitouchSupport.framework";

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


CPSGetCurrentProcessFunction *GetCPSGetCurrentProcessFunction(void) {
    static dispatch_once_t onceToken;
    static CPSGetCurrentProcessFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kApplicationServicesFramework, "CPSGetCurrentProcess");
    });
    return function;
}

CPSStealKeyFocusFunction *GetCPSStealKeyFocusFunction(void) {
    static dispatch_once_t onceToken;
    static CPSStealKeyFocusFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kApplicationServicesFramework, "CPSStealKeyFocus");
    });
    return function;
}

CPSReleaseKeyFocusFunction *GetCPSReleaseKeyFocusFunction(void) {
    static dispatch_once_t onceToken;
    static CPSReleaseKeyFocusFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kApplicationServicesFramework, "CPSReleaseKeyFocus");
    });
    return function;
}

CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void) {
    static BOOL tried = NO;
    static CGSSetWindowBackgroundBlurRadiusFunction *function = NULL;
    if (!tried) {
        function  = GetFunctionByName(kApplicationServicesFramework,
                                      "CGSSetWindowBackgroundBlurRadius");
        tried = YES;
    }
    return function;
}

MTActuatorCreateFromDeviceIDFunction *iTermGetMTActuatorCreateFromDeviceIDFunction(void) {
    static dispatch_once_t onceToken;
    static MTActuatorCreateFromDeviceIDFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kMultitouchSupportFramework,
                                     "MTActuatorCreateFromDeviceID");
    });
    return function;
}

MTActuatorOpenFunction *iTermGetMTActuatorOpenFunction(void) {
    static dispatch_once_t onceToken;
    static MTActuatorOpenFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kMultitouchSupportFramework,
                                     "MTActuatorOpen");
    });
    return function;
}

MTActuatorCloseFunction *iTermGetMTActuatorCloseFunction(void) {
    static dispatch_once_t onceToken;
    static MTActuatorCloseFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kMultitouchSupportFramework,
                                     "MTActuatorClose");
    });
    return function;
}

MTActuatorActuateFunction *iTermGetMTActuatorActuateFunction(void) {
    static dispatch_once_t onceToken;
    static MTActuatorActuateFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kMultitouchSupportFramework,
                                     "MTActuatorActuate");
    });
    return function;
}

MTActuatorIsOpenFunction *iTermGetMTActuatorIsOpenFunction(void) {
    static dispatch_once_t onceToken;
    static MTActuatorIsOpenFunction *function;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(kMultitouchSupportFramework,
                                     "MTActuatorIsOpen");
    });
    return function;
}


@implementation NSOpenPanel (Utility)
- (NSArray *)legacyFilenames {
    NSMutableArray *filenames = [NSMutableArray array];
    for (NSURL *url in self.URLs) {
        [filenames addObject:url.path];
    }
    return filenames;
}
@end

@implementation NSFont(Future)

- (BOOL)futureShouldAntialias {
    typedef BOOL CTFontShouldAntialiasFunction(CTFontRef);
    static CTFontShouldAntialiasFunction *function = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        function = GetFunctionByName(@"/System/Library/Frameworks/ApplicationServices.framework",
                                     "CTFontShouldAntiAlias");
    });
    if (function) {
        return function((CTFontRef)self);
    }
    return NO;
}

@end

@implementation NSValue(Future)

+ (NSValue *)futureValueWithEdgeInsets:(NSEdgeInsets)edgeInsets {
    return [[[NSValue alloc] initWithBytes:&edgeInsets objCType:@encode(NSEdgeInsets)] autorelease];
}

- (NSEdgeInsets)futureEdgeInsetsValue {
    NSEdgeInsets edgeInsets;
    [self getValue:&edgeInsets];
    return edgeInsets;
}

@end
