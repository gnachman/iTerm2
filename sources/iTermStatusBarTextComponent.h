//
//  iTermStatusBarTextComponent.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/29/18.
//

#import <Foundation/Foundation.h>
#import "iTermStatusBarBaseComponent.h"

NS_ASSUME_NONNULL_BEGIN

// A base class for components that show text.
// This class only knows how to show static text. Subclasses may choose to configure it by overriding
// stringValue, attributedStringValue, statusBarComponentVariableDependencies,
// statusBarComponentUpdateCadence, and statusBarComponentUpdate.
@interface iTermStatusBarTextComponent : iTermStatusBarBaseComponent

@property (nonatomic, readonly, nullable) NSString *stringValue;
@property (nonatomic, readonly, nullable) NSAttributedString *attributedStringValue;
@property (nonatomic, readonly) NSTextField *textField;

// Subclasses can override these if they can compress the string depending on available space.
@property (nonatomic, readonly, nullable) NSString *stringValueForCurrentWidth;
@property (nonatomic, readonly, nullable) NSString *maximallyCompressedStringValue;

- (void)setStringValue:(NSString *)stringValue;
- (CGFloat)widthForString:(NSString *)string;
- (void)updateTextFieldIfNeeded;

@end

NS_ASSUME_NONNULL_END
