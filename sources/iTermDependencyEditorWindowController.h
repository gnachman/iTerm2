//
//  iTermDependencyEditorWindowController.h
//  iTerm2
//
//  Created by George Nachman on 1/12/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermDependencyEditorWindowController : NSWindowController

+ (instancetype)sharedInstance;
- (void)open;

@end

NS_ASSUME_NONNULL_END
