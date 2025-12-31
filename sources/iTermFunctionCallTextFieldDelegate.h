//
//  iTermFunctionCallTextFieldDelegate.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/19/18.
//

#import <Cocoa/Cocoa.h>
#import "iTermFocusReportingTextField.h"
#import "iTermFunctionCallSuggester.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermFunctionCallTextFieldDelegate : NSObject<iTermFocusReportingTextFieldDelegate>

@property (nonatomic, strong, nullable) IBOutlet NSTextField *textField;
@property (nonatomic, weak, nullable) id passthrough;

@property (nonatomic) BOOL canWarnAboutContextMistake;
@property (nonatomic, copy, nullable) NSString *contextMistakeText;
@property (nonatomic, readonly) BOOL functionsOnly;

// If passthrough is nonnil then controlTextDidBeginEditing and controlTextDidEndEditing get called
// on it.
// If functionsOnly is NO, any legal expression is accepted (strings, ints,
// variable references, function calls). Otherwise, only suggestions for
// a top-level function call will be made. It may, of course, have expressions
// for argument values.
- (instancetype)initWithPathSource:(NSSet<NSString *> *(^)(NSString *prefix))pathSource
                       passthrough:(id _Nullable)passthrough
                     functionsOnly:(BOOL)functionsOnly;

- (instancetype)initForExpressionsWithPathSource:(NSSet<NSString *> *(^)(NSString *))pathSource
                                     passthrough:(id _Nullable)passthrough;

- (instancetype)initWithPathSource:(NSSet<NSString *> *(^)(NSString *))pathSource
                       passthrough:(id _Nullable)passthrough
                         suggester:(id<iTermFunctionCallSuggester>)suggester
                     functionsOnly:(BOOL)functionsOnly NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (BOOL)smellsLikeSessionContext:(NSString *)string;

@end

NS_ASSUME_NONNULL_END

