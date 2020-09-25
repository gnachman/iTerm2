//
//  iTermEditSnippetsWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/20/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermEditSnippetsWindowController : NSWindowController
@property (nonatomic, copy) NSString *guid;

- (void)windowWillOpen;

@end

NS_ASSUME_NONNULL_END
