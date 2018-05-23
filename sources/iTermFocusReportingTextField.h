//
//  iTermFocusReportingTextField.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import <Cocoa/Cocoa.h>

@class iTermFocusReportingTextField;

@protocol iTermFocusReportingTextFieldDelegate<NSTextFieldDelegate>
- (void)focusReportingTextFieldWillBecomeFirstResponder:(iTermFocusReportingTextField *)sender;
@end

@interface iTermFocusReportingTextField : NSTextField

@property (nullable, weak) id<iTermFocusReportingTextFieldDelegate> delegate;

@end
