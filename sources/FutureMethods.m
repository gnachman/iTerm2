//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"

static NSString *const kApplicationServicesFramework = @"/System/Library/Frameworks/ApplicationServices.framework";

@implementation NSScreen (future)

+ (BOOL)futureScreensHaveSeparateSpaces {
    if ([self respondsToSelector:@selector(screensHaveSeparateSpaces)]) {
        return [self screensHaveSeparateSpaces];
    } else {
        return NO;
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

@implementation NSOpenPanel (Utility)
- (NSArray *)legacyFilenames {
    NSMutableArray *filenames = [NSMutableArray array];
    for (NSURL *url in self.URLs) {
        [filenames addObject:url.path];
    }
    return filenames;
}
@end

@implementation NSSavePanel (Utility)
- (NSInteger)legacyRunModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes {
    if (path) {
        self.directoryURL = [NSURL fileURLWithPath:path];
    }
    if (name) {
        self.nameFieldStringValue = name;
    }
    if (fileTypes) {
        self.allowedFileTypes = fileTypes;
    }
    return [self runModal];
}

- (NSInteger)legacyRunModalForDirectory:(NSString *)path file:(NSString *)name {
    return [self legacyRunModalForDirectory:path file:name types:nil];
}

- (NSString *)legacyDirectory {
    return [[self directoryURL] path];
}

- (NSString *)legacyFilename {
    return [[self URL] path];
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

@implementation FutureWKWebViewConfiguration

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKWebViewConfiguration");
    return [theClass alloc];
}

@end

@implementation FutureWKPreferences

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKPreferences");
    return [theClass alloc];
}

@end

@implementation FutureWKProcessPool

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKProcessPool");
    return [theClass alloc];
}

@end

@implementation FutureWKUserContentController

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKUserContentController");
    return [theClass alloc];
}

@end

@implementation FutureWKWebsiteDataStore

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKWebsiteDataStore");
    return [theClass alloc];
}

+ (instancetype)defaultDataStore {
    Class theClass = NSClassFromString(@"WKWebsiteDataStore");
    return [theClass defaultDataStore];
}

@end

@implementation FutureWKWebView

+ (instancetype)alloc {
    Class theClass = NSClassFromString(@"WKWebView");
    return [theClass alloc];
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
