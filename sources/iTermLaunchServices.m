//
//  iTermLaunchServices.m
//  iTerm2
//
//  Created by George Nachman on 1/6/16.
//
//

#import "iTermLaunchServices.h"

@implementation iTermLaunchServices

+ (void)makeITermDefaultTerminal {
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    [self setDefaultTerminal:iTermBundleId];
}

+ (void)makeTerminalDefaultTerminal {
    [self setDefaultTerminal:@"com.apple.terminal"];
}

+ (BOOL)iTermIsDefaultTerminal {
    LSSetDefaultHandlerForURLScheme((CFStringRef)@"iterm2",
                                    (CFStringRef)[[NSBundle mainBundle] bundleIdentifier]);
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    CFStringRef unixHandler = LSCopyDefaultRoleHandlerForContentType(unixExecutableContentType, kLSRolesShell);
    NSString *iTermBundleId = [[NSBundle mainBundle] bundleIdentifier];
    BOOL result = [iTermBundleId isEqualToString:(NSString *)unixHandler];
    if (unixHandler) {
        CFRelease(unixHandler);
    }
    return result;
}

+ (void)setDefaultTerminal:(NSString *)bundleId {
    CFStringRef unixExecutableContentType = (CFStringRef)@"public.unix-executable";
    LSSetDefaultRoleHandlerForContentType(unixExecutableContentType,
                                          kLSRolesShell,
                                          (CFStringRef) bundleId);
}


@end
