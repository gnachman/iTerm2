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
@property(nonatomic, copy) void (^completion)(int);

+ (instancetype)announcementWithTitle:(NSString *)title
                                style:(iTermAnnouncementViewStyle)style
                          withActions:(NSArray *)actions
                           completion:(void (^)(int))completion;

- (void)dismiss;

// Amount of time announcement will stay onscreen before autodismissing.
- (void)setTimeout:(NSTimeInterval)timeout;

// Called when the announcement is displayed to the user.
- (void)didBecomeVisible;

// Indicates if it has timed out.
- (BOOL)shouldBecomeVisible;

@end
