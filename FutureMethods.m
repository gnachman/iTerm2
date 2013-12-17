//
//  FutureMethods.m
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "FutureMethods.h"

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

