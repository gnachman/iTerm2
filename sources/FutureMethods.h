//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>
// This is for the args to CGSSetWindowBackgroundBlurRadiusFunction, which is used for window-blurring using undocumented APIs.
#import <CGSInternal/CGSInternal.h>
#import "iTermCPS.h"

typedef CGError CGSSetWindowBackgroundBlurRadiusFunction(CGSConnectionID cid, CGSWindowID wid, NSUInteger blur);
CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void);

// Fills in its argument with the current process's serial number.
typedef OSErr CPSGetCurrentProcessFunction(CPSProcessSerNum *);

// Grabs keyboard focus; key events are directed to the key window although the app is inactive.
typedef OSErr CPSStealKeyFocusFunction(CPSProcessSerNum *);

// Undeso CPSStealKeyFocus
typedef OSErr CPSReleaseKeyFocusFunction(CPSProcessSerNum *);

// Returns a function pointer to CPSGetCurrentProcess(), or nil.
CPSGetCurrentProcessFunction *GetCPSGetCurrentProcessFunction(void);

// Returns a function pointer to CPSStealKeyFocus(), or nil.
CPSStealKeyFocusFunction *GetCPSStealKeyFocusFunction(void);

// Returns a function pointer to CPSReleaseKeyFocus(), or nil.
CPSReleaseKeyFocusFunction *GetCPSReleaseKeyFocusFunction(void);

#pragma mark - MultitouchSupport

typedef CFTypeRef MTActuatorCreateFromDeviceIDFunction(UInt64 deviceID);
typedef IOReturn MTActuatorOpenFunction(CFTypeRef actuatorRef);
typedef IOReturn MTActuatorCloseFunction(CFTypeRef actuatorRef);
typedef IOReturn MTActuatorActuateFunction(CFTypeRef actuatorRef, SInt32 actuationID, UInt32 unknown1, Float32 unknown2, Float32 unknown3);
typedef bool MTActuatorIsOpenFunction(CFTypeRef actuatorRef);

MTActuatorCreateFromDeviceIDFunction *iTermGetMTActuatorCreateFromDeviceIDFunction(void);
MTActuatorOpenFunction *iTermGetMTActuatorOpenFunction(void);
MTActuatorCloseFunction *iTermGetMTActuatorCloseFunction(void);
MTActuatorActuateFunction *iTermGetMTActuatorActuateFunction(void);
MTActuatorIsOpenFunction *iTermGetMTActuatorIsOpenFunction(void);

NS_INLINE BOOL iTermTextIsMonochromeOnMojave(void) NS_AVAILABLE_MAC(10_14) {
    if (@available(macOS 10.16, *)) {
        // Issue 9209
        return YES;
    }
    static dispatch_once_t onceToken;
    static BOOL subpixelAAEnabled;
    dispatch_once(&onceToken, ^{
        NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:@"CGFontRenderingFontSmoothingDisabled"];
        if (!number) {
            subpixelAAEnabled = NO;
        } else {
            subpixelAAEnabled = !number.boolValue;
        }
    });
    return !subpixelAAEnabled;
}

NS_INLINE BOOL iTermTextIsMonochrome(void) {
    return iTermTextIsMonochromeOnMojave();
}

@interface NSFont (Future)
// Does this font look bad without anti-aliasing? Relies on a private method.
- (BOOL)futureShouldAntialias;
@end

@interface NSValue (Future)

+ (NSValue *)futureValueWithEdgeInsets:(NSEdgeInsets)edgeInsets;
- (NSEdgeInsets)futureEdgeInsetsValue;

@end

#ifndef MAC_OS_VERSION_12_0
@interface NSProcessInfo(iTermMonterey)
- (BOOL)isLowPowerModeEnabled;
@end
#endif  // MAC_OS_VERSION_12_0
