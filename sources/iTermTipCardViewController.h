//
//  iTermWelcomeCardViewController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@class iTermTipCardActionButton;

@interface iTermTipCardViewController : NSViewController

- (void)setTitleString:(NSString *)titleString;
- (void)setColor:(NSColor *)color;
- (void)setBodyText:(NSString *)bodyText;
- (void)layoutWithWidth:(CGFloat)width animated:(BOOL)animated origin:(NSPoint)newOrigin;
- (iTermTipCardActionButton *)addActionWithTitle:(NSString *)title
                                            icon:(NSImage *)image
                                           block:(void (^)(id card))block;
- (iTermTipCardActionButton *)actionWithTitle:(NSString *)title;
- (void)removeActionWithTitle:(NSString *)title;
- (NSSize)sizeThatFits:(NSSize)size;

@end
