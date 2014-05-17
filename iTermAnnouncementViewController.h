//
//  iTermAnnouncement.h
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermAnnouncementView.h"

@class iTermAnnouncementViewController;

@protocol iTermAnnouncementDelegate
- (void)announcementWillDismiss:(iTermAnnouncementViewController *)announcement;
@end

@interface iTermAnnouncementViewController : NSViewController

@property(nonatomic, assign) id<iTermAnnouncementDelegate> delegate;

+ (instancetype)announcemenWithTitle:(NSString *)title
                               style:(iTermAnnouncementViewStyle)style
                         withActions:(NSArray *)actions
                          completion:(void (^)(int))completion;

- (void)dismiss;

@end
