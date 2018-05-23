//
//  iTermFunctionCallTextFieldDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermFocusReportingTextField.h"

@interface iTermFunctionCallTextFieldDelegate : NSObject<iTermFocusReportingTextFieldDelegate>

@property (nonatomic, strong) IBOutlet NSTextField *textField;

// If passthrough is nonnil then controlTextDidBeginEditing and controlTextDidEndEditing get called
// on it.
- (instancetype)initWithPaths:(NSArray<NSString *> *)paths
                  passthrough:(id)passthrough;

@end
