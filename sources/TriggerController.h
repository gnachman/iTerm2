//
//  TriggerController.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"
#import "iTermFocusReportingTextField.h"

@class CPKColorWell;
@class Trigger;
@class TriggerController;

extern NSString *const kTextColorWellIdentifier;
extern NSString *const kBackgroundColorWellIdentifier;

@protocol TriggerDelegate <NSObject>
- (void)triggerChanged:(TriggerController *)controller newValue:(NSArray *)value;
- (void)triggerSetUseInterpolatedStrings:(BOOL)useInterpolatedStrings;
- (void)triggersCloseSheet;

@optional
- (void)triggersCopyToProfile;
@end

@protocol iTermTriggerParameterController<NSObject, NSTextFieldDelegate, iTermFocusReportingTextFieldDelegate>
- (void)parameterPopUpButtonDidChange:(id)sender;
@end

@interface TriggerController : NSWindowController <NSWindowDelegate>

@property (nonatomic, copy) NSString *guid;
@property (nonatomic) BOOL hasSelection;
@property (nonatomic, weak) IBOutlet id<TriggerDelegate> delegate;
@property (nonatomic, readonly) NSTableView *tableView;

+ (NSArray<Class> *)triggerClasses;
+ (NSView *)viewForParameterForTrigger:(Trigger *)trigger
                                  size:(CGSize)size
                                 value:(id)value
                              receiver:(id<iTermTriggerParameterController>)receiver
                   interpolatedStrings:(BOOL)interpolatedStrings
                           delegateOut:(out id *)delegateOut
                           wellFactory:(CPKColorWell *(^ NS_NOESCAPE)(NSRect, NSColor *))wellFactory;

- (void)windowWillOpen;
- (void)profileDidChange;

@end

