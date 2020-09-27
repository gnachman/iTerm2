//
//  iTermEditActionsWindowController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/20.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermEditActionsWindowController : NSWindowController
@property (nonatomic, copy) NSString *guid;

- (void)windowWillOpen;

@end

NS_ASSUME_NONNULL_END
