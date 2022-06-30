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
@property (nonatomic, weak) id passthrough;

@property (nonatomic) BOOL canWarnAboutContextMistake;
@property (nonatomic, copy) NSString *contextMistakeText;

// If passthrough is nonnil then controlTextDidBeginEditing and controlTextDidEndEditing get called
// on it.
// If functionsOnly is NO, any legal expression is accepted (strings, ints,
// variable references, function calls). Otherwise, only suggestions for
// a top-level function call will be made. It may, of course, have expressions
// for argument values.
- (instancetype)initWithPathSource:(NSSet<NSString *> *(^)(NSString *prefix))pathSource
                       passthrough:(id)passthrough
                     functionsOnly:(BOOL)functionsOnly NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)smellsLikeSessionContext:(NSString *)string;

@end
