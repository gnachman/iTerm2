//
//  iTermDynamicProfileManager.h
//  iTerm2
//
//  Created by George Nachman on 12/30/15.
//
//

#import <Foundation/Foundation.h>

@interface iTermDynamicProfileManager : NSObject

+ (instancetype)sharedInstance;

// Load the profiles from |filename| and add valid profiles into |profiles|.
// Add their guids to |guids|.
- (BOOL)loadDynamicProfilesFromFile:(NSString *)filename
                          intoArray:(NSMutableArray *)profiles
                              guids:(NSMutableSet *)guids;

// Immediately examine the dynamic profiles files to see if they've changed and update the model
// if needed.
- (void)reloadDynamicProfiles;

@end
