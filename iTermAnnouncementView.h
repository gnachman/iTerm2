//
//  iTermAnnouncementView.h
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import <Cocoa/Cocoa.h>

@interface iTermAnnouncementView : NSView

- (void)createButtonsFromActions:(NSArray *)actions block:(void (^)(int index))block;
- (void)setTitle:(NSString *)title;

@end
