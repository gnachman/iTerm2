//
//  iTermAnnouncement.m
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import "iTermAnnouncementViewController.h"
#import "iTermAnnouncementView.h"
#import "SolidColorView.h"

@interface iTermAnnouncementViewController ()
@property(nonatomic, copy) NSArray *actions;
@property(nonatomic, copy) void (^completion)(int);
@end

@implementation iTermAnnouncementViewController {
    BOOL _dismissing;
}

+ (instancetype)announcemenWithTitle:(NSString *)title
                         withActions:(NSArray *)actions
                          completion:(void (^)(int))completion {
    iTermAnnouncementViewController *announcement = [[[self alloc] init] autorelease];
    announcement.title = title;
    announcement.actions = actions;
    announcement.completion = completion;
    return announcement;
}

- (void)dealloc {
    [_actions release];
    [_completion release];
    [super dealloc];
}

- (void)loadView {
    self.view = [iTermAnnouncementView announcementViewWithTitle:self.title
                                                           style:kiTermAnnouncementViewStyleWarning
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
        [_delegate announcementWillDismiss:self];
    }
}

@end
