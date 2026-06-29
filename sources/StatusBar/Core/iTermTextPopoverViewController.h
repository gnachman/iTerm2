//
//  iTermTextPopoverViewController.h
//  iTerm2
//
//  Created by George Nachman on 1/21/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat iTermTextPopoverViewControllerHorizontalMarginWidth;

@interface iTermTextPopoverViewController : NSViewController<NSTextViewDelegate>

@property (nonatomic, strong) IBOutlet NSPopover *popover;
@property (nonatomic, strong) IBOutlet NSTextView *textView;
@property (nonatomic, readonly) NSDictionary *defaultAttributes;
@property (nonatomic) BOOL closeOnLinkClick;
@property (nonatomic) CGFloat maxHeight;

- (void)appendString:(NSString *)string;
- (void)appendAttributedString:(NSAttributedString *)string;
- (void)sizeToFit;

@end

NS_ASSUME_NONNULL_END
