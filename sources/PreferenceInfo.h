//
//  PreferenceInfo.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, PreferenceInfoType) {
    kPreferenceInfoTypeCheckbox,
    kPreferenceInfoTypeInvertedCheckbox,  // true=checked, false=unchecked. Handy when inverting a checkbox's text, but the user defaults key can't be changed.
    kPreferenceInfoTypeIntegerTextField,  // 32bit values only
    kPreferenceInfoTypeUnsignedIntegerTextField,
    kPreferenceInfoTypeDoubleTextField,
    kPreferenceInfoTypeStringTextField,
    kPreferenceInfoTypePopup,
    kPreferenceInfoTypeUnsignedIntegerPopup,
    kPreferenceInfoTypeSlider,
    kPreferenceInfoTypeTokenField,
    kPreferenceInfoTypeMatrix,
    kPreferenceInfoTypeColorWell,
    // a view whose children that are buttons are all radio buttons with distinct tags controlling the same preference
    kPreferenceInfoTypeRadioButton
};

@class iTermPreferencesSearchDocument;

@interface PreferenceInfo : NSObject

@property(nonatomic, strong) NSString *key;
@property(nonatomic) PreferenceInfoType type;
@property(nonatomic, strong) NSControl *control;
@property(nonatomic) NSRange range;  // For integer fields, the range of legal values.
@property(nonatomic, readonly) NSArray<NSString *> *searchKeywords;

// If set to YES, don't process changes until keyboard focus exits the control. Defaults to NO.
// Only supported on controls of type kPreferenceInfoTypeIntegerTextField.
@property(nonatomic) BOOL deferUpdate;

// A function that indicates if the control should be enabled. If nil, then the control is always
// enabled.
@property(nonatomic, copy) BOOL (^shouldBeEnabled)(void);

// Called when the user changes a control's value by interacting with it (after the underlying user
// default or profile is update), or after its value is changed programmatically. It is also invoked
// when the preference panel finishes loading. It should be idempotent.
// This is typically used when changing one view's value affects another view's appearance. For
// example, if turning on a checkbox causes a view to appear, the checkbox's observer would update
// the view's hidden flag.
@property(nonatomic, copy) void (^observer)(void);

// Called when the user changes a control's value by interacting with it.
// This is typically used when changing a control triggers an event beyond simply updating the
// display style. For example, it might open a file picker dialog or register for a hotkey.
@property(nonatomic, copy) void (^onChange)(void);

// Called when a user interacts with a control, changing its value. This is called before anything
// else happens (such as invoking customSettingChangedHandler()) or updating user defaults.
// This isn't used much. It is meant to be used when a user changing a control's value would cause
// irreparable harm (for example, renaming a profile while there is a search filter in place, such
// that the renamed profile would no longer match the filter), and is the last chance to mitigate
// the damage.
@property(nonatomic, copy) void (^willChange)(void);

// Called before a control's value is changed programmatically (e.g., when a different profile is
// selected). If it returns YES, the normal path is not taken, and the block is responsible for
// updating the control to reflect the user preference.
// This is normally used on popups and matrixes to update the control to reflect the
// user preference.
@property(nonatomic, copy) BOOL (^onUpdate)(void);

// Replaces the default settingChanged: handler, which updates user defaults and calls onChange.
// It is called when the user interacts with a control, changing its value.
// This is normally used on popups and matrixes to update user defaults to reflect the control's
// state.
@property(nonatomic, copy) void (^customSettingChangedHandler)(id sender);

// For text controls, this is called when editing ends.
@property(nonatomic, copy) void (^controlTextDidEndEditing)(NSNotification *notification);

+ (instancetype)infoForPreferenceWithKey:(NSString *)key
                                    type:(PreferenceInfoType)type
                                 control:(NSControl *)control;

@end
