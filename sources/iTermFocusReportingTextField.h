//
//  iTermFocusReportingTextField.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class iTermFocusReportingTextField;

@protocol iTermFocusReportingTextFieldDelegate<NSTextFieldDelegate>
@optional
- (void)focusReportingTextFieldWillBecomeFirstResponder:(iTermFocusReportingTextField *)sender;
@end

@interface iTermFocusReportingTextField : NSTextField

@property (nullable, weak) id<iTermFocusReportingTextFieldDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
