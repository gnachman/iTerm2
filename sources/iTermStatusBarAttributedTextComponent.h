//
//  iTermStatusBarAttributedTextComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/22/18.
//

#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

// WARNING! This doesn't support most features of attributed strings. This uses
// a terrible hack to work around an NSTextField bug.
@interface iTermStatusBarAttributedTextComponent : iTermStatusBarBaseComponent

@property (nonatomic, readonly) NSArray<NSAttributedString *> *attributedStringVariants;

@property (nonatomic, readonly) NSTextField *textField;

- (CGFloat)widthForAttributedString:(NSAttributedString *)string;
- (void)updateTextFieldIfNeeded;

@end

NS_ASSUME_NONNULL_END
