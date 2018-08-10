//
//  NSAppearance+iTerm.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 8/9/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferences.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSAppearance (iTerm)

// Converts a tab style if automatic.
- (iTermPreferencesTabStyle)it_tabStyle:(iTermPreferencesTabStyle)tabStyle;

@end

NS_ASSUME_NONNULL_END
