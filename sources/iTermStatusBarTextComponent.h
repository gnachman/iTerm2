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

- (void)setStringValue:(NSString *)stringValue;

@end

NS_ASSUME_NONNULL_END
