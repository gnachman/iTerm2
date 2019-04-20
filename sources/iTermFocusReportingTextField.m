//
//  iTermFocusReportingTextField.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/22/18.
//

#import "iTermFocusReportingTextField.h"

@implementation iTermFocusReportingTextField

@dynamic delegate;

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result &&
        [self.delegate respondsToSelector:@selector(focusReportingTextFieldWillBecomeFirstResponder:)]) {
        [self.delegate focusReportingTextFieldWillBecomeFirstResponder:self];
    }
    return result;
}

@end

@implementation iTermFocusReportingSearchField

@dynamic delegate;

- (BOOL)becomeFirstResponder {
    BOOL result = [super becomeFirstResponder];
    if (result &&
        [self.delegate respondsToSelector:@selector(focusReportingSearchFieldWillBecomeFirstResponder:)]) {
        [self.delegate focusReportingSearchFieldWillBecomeFirstResponder:self];
    }
    return result;
}

@end
