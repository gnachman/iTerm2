//
//  iTermMissionControlHacks.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/20.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermMissionControlHacks : NSObject

// Space is 1-indexed
+ (void)switchToSpace:(int)space;

@end

NS_ASSUME_NONNULL_END
