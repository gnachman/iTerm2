//
//  iTermWelcomeCardActionButton.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermTipCardActionButton : NSButton

@property (nonatomic, copy) void (^block)();

- (void)setTitle:(NSString *)title;
- (void)setIcon:(NSImage *)image;

@end
