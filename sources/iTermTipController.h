//
//  iTermTipController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Foundation/Foundation.h>

// Manages the tip of the day. NOTE: Only supports OS 10.10+. Will return a nil
// sharedInstance on older OSes.
@interface iTermTipController : NSObject

+ (instancetype)sharedInstance;

// Call this when the app finishes launching to show the initial card.
- (void)applicationDidFinishLaunching;

@end
