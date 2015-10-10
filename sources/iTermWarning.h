#import <Cocoa/Cocoa.h>

@protocol iTermWarningHandler <NSObject>

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier;

@end
// The type of warning.
typedef NS_ENUM(NSInteger, iTermWarningType) {
    kiTermWarningTypePersistent,
    kiTermWarningTypePermanentlySilenceable,
    kiTermWarningTypeTemporarilySilenceable  // 10 minutes
};

typedef NS_ENUM(NSInteger, iTermWarningSelection) {
    kiTermWarningSelection0,  // First passed-in action
    kiTermWarningSelection1,  // Second passed-in action
    kiTermWarningSelection2,  // Third passed-in action
    kItermWarningSelectionError,  // Something went wrong.
};

@interface iTermWarning : NSObject

// Tests can use this to prevent warning popups.
+ (void)setWarningHandler:(id<iTermWarningHandler>)handler;
+ (id<iTermWarningHandler>)warningHandler;
+ (BOOL)showingWarning;

// Show a warning, optionally with a suppression checkbox. It may not be shown
// if it was previously suppressed.
+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType;

+ (iTermWarningSelection)showWarningWithTitle:(NSString *)title
                                      actions:(NSArray *)actions
                                    accessory:(NSView *)accessory
                                   identifier:(NSString *)identifier
                                  silenceable:(iTermWarningType)warningType
                                      heading:(NSString *)heading;

@end
