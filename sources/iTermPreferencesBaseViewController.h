//
//  iTermPreferencesBaseViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferences.h"
#import "PreferenceInfo.h"

// Used in preferenceDidChangeFromOtherPanel:'s notification's user info dictionary.
extern NSString *const kPreferenceDidChangeFromOtherPanelKeyUserInfoKey;

// View controllers for tabs in the Preferences dialog inherit from this class. Consider it
// abstract. The pattern is to call -defineControl:key:type: in -awakeFromNib for each control.
// In IB, assign all controls the -settingChanged: selector, and for text fields, make your view
// controller the delegate.
@interface iTermPreferencesBaseViewController : NSViewController

@property(nonatomic, readonly) NSMapTable *keyMap;
@property(nonatomic, readonly) NSArray *keysForBulkCopy;

// This is used to release preference info objects when the owning window
// controller goes away because there is a hard-to-remove retain cycle when
// blocks are used (e.g., for observers).
@property(nonatomic, assign) NSWindowController *preferencePanel;

#pragma mark - Core Methods

// Bind a preference control to a key defined in iTermPreferences.
- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type;

// Define a control with a custom settingChanged and update handler. If they're both not null then
// the default value is not type checked.
- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^)(id))settingChanged
                           update:(BOOL (^)())update;

#pragma mark - IBActions

// Standard selector invoked by controls when their values changed, bound in XIB file.
- (IBAction)settingChanged:(id)sender;

#pragma mark - Helpers

// Enable or disable controls as needed.
- (void)updateEnabledState;

// Update a control's value.
- (void)updateValueForInfo:(PreferenceInfo *)info;

// Update a control's enabled state.
- (void)updateEnabledStateForInfo:(PreferenceInfo *)info;

// Returns PreferenceInfo for a control bound with defineControl:key:type:.
- (PreferenceInfo *)infoForControl:(NSControl *)control;

- (void)postRefreshNotification;

#pragma mark - Methods to override

// Just a convenience method in the base class, but subclasses can use this to be "more atomic".
- (void)setObjectsFromDictionary:(NSDictionary *)dictionary;

// By default, this class uses iTermPreferences class methods to change settings. Override these
// methods to use a different model.
- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;

- (int)intForKey:(NSString *)key;
- (void)setInt:(int)value forKey:(NSString *)key;

- (NSInteger)integerForKey:(NSString *)key;
- (void)setInteger:(NSInteger)value forKey:(NSString *)key;

- (NSUInteger)unsignedIntegerForKey:(NSString *)key;
- (void)setUnsignedInteger:(NSUInteger)value forKey:(NSString *)key;

- (double)floatForKey:(NSString *)key;
- (void)setFloat:(double)value forKey:(NSString *)key;

- (double)doubleForKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;

- (NSString *)stringForKey:(NSString *)key;
- (void)setString:(NSString *)value forKey:(NSString *)key;

- (BOOL)keyHasDefaultValue:(NSString *)key;
- (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;

- (void)setObject:(NSObject *)object forKey:(NSString *)key;
- (NSObject *)objectForKey:(NSString *)key;

// If this returns YES, then changes to this panel will post a notification causing other panels to
// update their values for the affected preference.
- (BOOL)shouldUpdateOtherPanels;

// Override this to handle updates of preferences from other panels.
- (void)preferenceDidChangeFromOtherPanel:(NSNotification *)notification NS_REQUIRES_SUPER;

// The prefs panel this view controller belongs to will close. This implementation does nothing.
- (void)windowWillClose;

@end
