//
//  iTermActionsMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import <AppKit/AppKit.h>

#import "iTermActionsModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSResponder (ApplyAction)
// -representedObject of sender is an iTermAction
- (void)applyAction:(id)sender;
@end

@interface iTermActionsMenuController : NSObject

@end

NS_ASSUME_NONNULL_END
