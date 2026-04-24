//
//  iTermWindowHacks.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/21/18.
//

#import <Foundation/Foundation.h>

@interface iTermWindowHacks : NSObject

// Block returns NO to stop. Receives YES if open, NO if closed.
+ (void)pollForCharacterPanelToOpenOrCloseWithCompletion:(BOOL (^)(BOOL))block;

@end
