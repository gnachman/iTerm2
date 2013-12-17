//
//  FutureMethods.h
//  iTerm
//
//  Created by George Nachman on 8/29/11.
//

#import <Cocoa/Cocoa.h>
// This is for the args to CGSSetWindowBackgroundBlurRadiusFunction, which is used for window-blurring using undocumented APIs.
#import "CGSInternal.h"


typedef CGError CGSSetWindowBackgroundBlurRadiusFunction(CGSConnectionID cid, CGSWindowID wid, NSUInteger blur);
CGSSetWindowBackgroundBlurRadiusFunction* GetCGSSetWindowBackgroundBlurRadiusFunction(void);

@interface NSOpenPanel (Utility)
- (NSArray *)legacyFilenames;
@end

@interface NSSavePanel (Utility)
- (NSInteger)legacyRunModalForDirectory:(NSString *)path file:(NSString *)name types:(NSArray *)fileTypes;
- (NSInteger)legacyRunModalForDirectory:(NSString *)path file:(NSString *)name;
- (NSString *)legacyFilename;
- (NSString *)legacyDirectory;
@end
