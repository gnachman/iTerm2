//
//  TriggerController.h
//  iTerm
//
//  Created by George Nachman on 9/23/11.
//

#import <Cocoa/Cocoa.h>
#import "FutureMethods.h"
#import "iTermFocusReportingTextField.h"
#import "iTermOptionallyBordered.h"

@class CPKColorWell;
@class ProfileModel;
@class Trigger;
@class TriggerController;

extern NSString *const kTextColorWellIdentifier;
extern NSString *const kBackgroundColorWellIdentifier;
extern NSString *const kTwoPraramNameColumnIdentifier;
extern NSString *const kTwoPraramValueColumnIdentifier;
extern NSString *const kStatusTextComboBoxIdentifier;

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
@property (nonatomic) BOOL browserMode;

- (instancetype)initInBrowserMode:(BOOL)browserMode;
+ (NSArray<Class> *)triggerClassesForTerminal:(BOOL)terminal;
+ (NSView *)viewForParameterForTrigger:(Trigger *)trigger
                                  size:(CGSize)size
                                 value:(id)value
                              receiver:(id<iTermTriggerParameterController>)receiver
                   interpolatedStrings:(BOOL)interpolatedStrings
                             tableView:(NSTableView *)tableView
                           delegateOut:(out id *)delegateOut
                           wellFactory:(CPKColorWell *(^ NS_NOESCAPE)(NSRect, NSColor *))wellFactory;
+ (void)importTriggersFromURL:(NSURL *)url;
+ (void)importTriggersFromFile:(NSString *)filename;
+ (NSArray<Trigger *> *)triggersFromFile:(NSString *)filename window:(NSWindow *)window;
+ (void)addTriggers:(NSArray<Trigger *> *)triggers toProfileWithGUID:(NSString *)guid;
+ (void)addTriggers:(NSArray<Trigger *> *)triggers
  toProfileWithGUID:(NSString *)guid
            inModel:(ProfileModel *)model;

- (void)windowWillOpen;
- (void)profileDidChange;

@end

