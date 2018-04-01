//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>
// This is for the args to CGSSetWindowBackgroundBlurRadiusFunction, which is used for window-blurring using undocumented APIs.
#import "CGSInternal.h"
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

@interface NSOpenPanel (Utility)
- (NSArray *)legacyFilenames;
@end

@interface NSFont (Future)
// Does this font look bad without anti-aliasing? Relies on a private method.
- (BOOL)futureShouldAntialias;
@end

@interface NSValue (Future)

+ (NSValue *)futureValueWithEdgeInsets:(NSEdgeInsets)edgeInsets;
- (NSEdgeInsets)futureEdgeInsetsValue;

@end
