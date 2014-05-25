//
//  iTermAnnouncementView.h
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import <Cocoa/Cocoa.h>

typedef enum {
    kiTermAnnouncementViewStyleWarning
} iTermAnnouncementViewStyle;

@interface iTermAnnouncementView : NSView

+ (id)announcementViewWithTitle:(NSString *)title
                          style:(iTermAnnouncementViewStyle)style
                        actions:(NSArray *)actions
                          block:(void (^)(int index))block;

- (void)sizeToFit;

@end
