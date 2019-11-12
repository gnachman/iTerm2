//
//  iTermFakeWindowTitleLabel.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 11/11/19.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermFakeWindowTitleLabel : NSTextField
@property (nonatomic, copy, readonly) NSString *windowTitle;
@property (nonatomic, strong, readonly) NSImage *windowIcon;

- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)initWithFrame:(NSRect)frameRect NS_UNAVAILABLE;

// Sets windowTitle and windowIcon. Then calls alignmentProvider with a scratch
// text field that has been initialized with the proper string, attributed
// string, font, and text color. The alignmentProvider must return a text
// alignment to use. That text alignment will be set on self.
//
// This is useful because this label's contents will be left-aligned or
// center-aligned in caller-defined circumstances (e.g., when long) based on
// the fitting size.
- (void)setTitle:(NSString *)title
            icon:(NSImage *)icon
alignmentProvider:(NSTextAlignment (^NS_NOESCAPE)(NSTextField *scratch))alignmentProvider;

@end

NS_ASSUME_NONNULL_END
