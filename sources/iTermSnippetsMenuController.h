//
//  iTermSnippetsMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/8/20.
//

#import <AppKit/AppKit.h>

#import "iTermSnippetsModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSResponder (Snippets)
// -representedObject of sender is an iTermSnippet.
- (void)sendSnippet:(id)sender;
@end

@interface iTermSnippetsMenuController : NSObject
@property (nonatomic, nullable, strong) NSMenu *menu;
@end

NS_ASSUME_NONNULL_END
