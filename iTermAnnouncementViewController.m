//
//  iTermAnnouncement.m
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import "iTermAnnouncementViewController.h"
#import "SolidColorView.h"

@interface iTermAnnouncementViewController ()
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, assign) iTermAnnouncementViewStyle style;
@end

@implementation iTermAnnouncementViewController {
    BOOL _dismissing;
}

+ (instancetype)announcemenWithTitle:(NSString *)title
                               style:(iTermAnnouncementViewStyle)style
                         withActions:(NSArray *)actions
                          completion:(void (^)(int))completion {
    iTermAnnouncementViewController *announcement = [[[self alloc] init] autorelease];
    announcement.title = title;
    announcement.actions = actions;
    announcement.completion = completion;
    announcement.style = style;
    return announcement;
}

- (void)dealloc {
    [_actions release];
    [_completion release];
    [super dealloc];
}

- (void)loadView {
    self.view = [iTermAnnouncementView announcementViewWithTitle:self.title
                                                           style:_style
                                                         actions:self.actions
                                                           block:^(int index) {
                                                               if (!_dismissing) {
                                                                   self.completion(index);
                                                                   [self dismiss];
                                                               }
                                                           }];
}

- (void)dismiss {
    if (!_dismissing) {
        _dismissing = YES;
        self.completion(-2);
        [_delegate announcementWillDismiss:self];
    }
}

@end
