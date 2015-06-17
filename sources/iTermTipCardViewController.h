//
//  iTermWelcomeCardViewController.h
//  iTerm2
//
//  Created by George Nachman on 6/16/15.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermTipCardViewController : NSViewController

- (void)setTitleString:(NSString *)titleString;
- (void)setColor:(NSColor *)color;
- (void)setBodyText:(NSString *)bodyText;
- (void)layoutWithWidth:(CGFloat)width;
- (void)addActionWithTitle:(NSString *)title
                      icon:(NSImage *)image
                     block:(void (^)())block;
@end
