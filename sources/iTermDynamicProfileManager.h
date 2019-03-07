//
//  iTermDynamicProfileManager.h
//  iTerm2
//
//  Created by George Nachman on 12/30/15.
//
//

#import <Foundation/Foundation.h>
#import "ProfileModel.h"

typedef NS_ENUM(NSUInteger, iTermDynamicProfileFileType) {
    kDynamicProfileFileTypeJSON,
    kDynamicProfileFileTypePropertyList,
};

@interface iTermDynamicProfileManager : NSObject

+ (instancetype)sharedInstance;

// Reads profiles from a dyamic profiles file.
- (NSArray<Profile *> *)profilesInFile:(NSString *)filename
                              fileType:(iTermDynamicProfileFileType *)fileType;

// Returns a JSON/Plist root element for a dynamic profiles file that contains `profiles`.
- (NSDictionary *)dictionaryForProfiles:(NSArray<Profile *> *)profiles;

// Load the profiles from |filename| and add valid profiles into |profiles|.
// Add their guids to |guids|.
- (BOOL)loadDynamicProfilesFromFile:(NSString *)filename
                          intoArray:(NSMutableArray *)profiles
                              guids:(NSMutableSet *)guids;

// Immediately examine the dynamic profiles files to see if they've changed and update the model
// if needed.
- (void)reloadDynamicProfiles;
- (void)revealProfileWithGUID:(NSString *)guid;

@end
