//
//  iTermAnnouncementView.h
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import <Cocoa/Cocoa.h>

typedef enum {
    kiTermAnnouncementViewStyleWarning,
    kiTermAnnouncementViewStyleQuestion
} iTermAnnouncementViewStyle;

@interface iTermAnnouncementView : NSView

+ (id)announcementViewWithTitle:(NSString *)title
                          style:(iTermAnnouncementViewStyle)style
                        actions:(NSArray *)actions
                          block:(void (^)(int index))block;

- (void)sizeToFit;

// We have a block which causes a retain cycle; call this before releasing the
// view controller to break the cycle.
- (void)willDismiss;

- (void)addDismissOnKeyDownLabel;

@end
