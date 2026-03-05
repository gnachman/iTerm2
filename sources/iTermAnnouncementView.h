//
//  iTermAnnouncementView.h
//  iTerm
//
//  Created by George Nachman on 5/16/14.
//
//

#import <Cocoa/Cocoa.h>

// Padding added to text height to compute total announcement view height.
extern const CGFloat iTermAnnouncementViewHeightPadding;

typedef NS_ENUM(NSInteger, iTermAnnouncementViewStyle) {
    kiTermAnnouncementViewStyleWarning,
    kiTermAnnouncementViewStyleQuestion
};

@interface iTermAnnouncementView : NSView
@property (nonatomic, strong)NSString *title;
@property (nonatomic) BOOL isMarkdown;

+ (NSFont *)announcementFont;
+ (CGFloat)estimatedHeightForWidth:(CGFloat)width text:(NSString *)text;

+ (instancetype)announcementViewWithTitle:(NSString *)title
                                    style:(iTermAnnouncementViewStyle)style
                                  actions:(NSArray *)actions
                                    block:(void (^)(int index))block;

+ (instancetype)announcementViewWithMarkdownTitle:(NSString *)title
                                            style:(iTermAnnouncementViewStyle)style
                                          actions:(NSArray *)actions
                                            block:(void (^)(int index))block;

- (void)sizeToFit;

// We have a block which causes a retain cycle; call this before releasing the
// view controller to break the cycle.
- (void)willDismiss;

- (void)addDismissOnKeyDownLabel;

- (void)selectIndex:(NSInteger)index;

@end
