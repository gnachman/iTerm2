//
//  iTermURLSchemeController.h
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import <Cocoa/Cocoa.h>
#import "ProfileModel.h"

@interface iTermURLSchemeController : NSObject

+ (instancetype)sharedInstance;
- (void)connectBookmarkWithGuid:(NSString*)guid toScheme:(NSString*)scheme;
- (void)disconnectHandlerForScheme:(NSString*)scheme;

// Returns the GUID that is assigned to the scheme, even if iTerm2 isn't registered for the scheme.
- (NSString *)guidForScheme:(NSString *)scheme;

// Returns the profile that is assigned to the scheme, returning nil if iTerm2 isn't registered for
// the scheme.
- (Profile *)profileForScheme:(NSString *)scheme;

@end
