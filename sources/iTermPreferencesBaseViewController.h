//
//  iTermPreferencesBaseViewController.h
//  iTerm
//
//  Created by George Nachman on 4/6/14.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermPreferences.h"
#import "iTermSearchableViewController.h"
#import "PreferenceInfo.h"

NS_ASSUME_NONNULL_BEGIN

@protocol iTermPreferencePanelSizing<NSObject>
- (CGFloat)preferencePanelMinimumWidth;
@end

// Post this notif if you change a setting that the settings panel should pick up. See the userinfo
// key below.
extern NSString *const kPreferenceDidChangeFromOtherPanel;

// Used in preferenceDidChangeFromOtherPanel:'s notification's user info dictionary.
extern NSString *const kPreferenceDidChangeFromOtherPanelKeyUserInfoKey;
extern NSString *const iTermPreferencesDidToggleIndicateNonDefaultValues;

// View controllers for tabs in the Preferences dialog inherit from this class. Consider it
// abstract. The pattern is to call -defineControl:key:type: in -awakeFromNib for each control.
// In IB, assign all controls the -settingChanged: selector, and for text fields, make your view
// controller the delegate.
@interface iTermPreferencesBaseViewController : NSViewController<iTermSearchableViewController, PreferenceController, NSTabViewDelegate, NSTextViewDelegate>

@property(nonatomic, readonly) NSMapTable *keyMap;
@property(nonatomic, readonly) NSArray<NSString *> *keysForBulkCopy;

@property(nonatomic, weak) NSWindowController<iTermPreferencePanelSizing> * _Nullable preferencePanel;
@property(nonatomic, readonly) NSMutableDictionary *internalState;

#pragma mark - Core Methods

// Swift subclases have to call this from init?(coder:)
- (void)commonInit;

// Bind a preference control to a key defined in iTermPreferences.
- (PreferenceInfo *)defineControl:(NSView *)control
                              key:(NSString *)key
                      relatedView:(NSView * _Nullable)relatedView
                             type:(PreferenceInfoType)type;

- (PreferenceInfo *)defineControl:(NSView *)control
                              key:(NSString *)key
                      displayName:(NSString * _Nullable)displayName // for search
                             type:(PreferenceInfoType)type;

- (PreferenceInfo *)defineUnsearchableControl:(NSView *)control
                                          key:(NSString *)key
                                         type:(PreferenceInfoType)type;

- (void)associateStepper:(NSStepper *)stepper withPreference:(PreferenceInfo *)info;

// Define a control with a custom settingChanged and update handler. If they're both not null then
// the default value is not type checked.
- (PreferenceInfo *)defineControl:(NSView *)control
                              key:(NSString *)key
                      relatedView:(NSView * _Nullable)relatedView
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^ _Nullable)(id))settingChanged
                           update:(BOOL (^ _Nullable)(void))update;

- (PreferenceInfo *)defineControl:(NSView *)control
                              key:(NSString *)key
                      displayName:(NSString * _Nullable)displayName // for search
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^ _Nullable)(id))settingChanged
                           update:(BOOL (^ _Nullable)(void))update;

- (PreferenceInfo *)defineControl:(NSView *)control
                              key:(NSString *)key
                      relatedView:(NSView * _Nullable)relatedView
                      displayName:(NSString * _Nullable)forceDisplayName
                             type:(PreferenceInfoType)type
                   settingChanged:(void (^ _Nullable)(id))settingChanged
                           update:(BOOL (^ _Nullable)(void))update
                       searchable:(BOOL)searchable;

// This can be useful for synthetic values.
- (PreferenceInfo *)unsafeDefineControl:(NSView *)control
                                    key:(NSString *)key
                            relatedView:(NSView * _Nullable)relatedView
                            displayName:(NSString * _Nullable)forceDisplayName
                                   type:(PreferenceInfoType)type
                         settingChanged:(void (^ _Nullable)(id))settingChanged
                                 update:(BOOL (^ _Nullable)(void))update
                             searchable:(BOOL)searchable;

- (void)setControl:(NSView *)control inPreference:(PreferenceInfo *)info;

- (void)addViewToSearchIndex:(NSView *)control
                 displayName:(NSString * _Nullable)displayName
                     phrases:(NSArray<NSString *> *)phrases
                         key:(NSString * _Nullable)key;

// Call this after defining controls.
- (void)commitControls;

#pragma mark - IBActions

// Standard selector invoked by controls when their values changed, bound in XIB file.
- (IBAction)settingChanged:(id _Nullable)sender;

#pragma mark - Helpers

// Enable or disable controls as needed.
- (void)updateEnabledState;

// Update a control's value.
- (void)updateValueForInfo:(PreferenceInfo *)info;

// Update a control's enabled state.
- (void)updateEnabledStateForInfo:(PreferenceInfo *)info;

// Returns PreferenceInfo for a control bound with defineControl:key:type:.
- (PreferenceInfo * _Nullable)infoForControl:(NSView *)control;
- (PreferenceInfo * _Nullable)safeInfoForControl:(NSView *)control;

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

- (NSString * _Nullable)stringForKey:(NSString *)key;
- (void)setString:(NSString * _Nullable)value forKey:(NSString *)key;

- (BOOL)keyHasDefaultValue:(NSString *)key;
- (BOOL)defaultValueForKey:(NSString *)key isCompatibleWithType:(PreferenceInfoType)type;
- (id)defaultValueForKey:(NSString *)key;

- (void)setObject:(NSObject * _Nullable)object forKey:(NSString *)key;
- (NSObject * _Nullable)objectForKey:(NSString *)key;

- (void)updateControlForKey:(NSString *)key;

- (BOOL)valueOfKeyEqualsDefaultValue:(NSString *)key;

// If this returns YES, then changes to this panel will post a notification causing other panels to
// update their values for the affected preference.
- (BOOL)shouldUpdateOtherPanels;

// Override this to handle updates of preferences from other panels.
- (void)preferenceDidChangeFromOtherPanel:(NSNotification * _Nullable)notification NS_REQUIRES_SUPER;

// The prefs panel this view controller belongs to will close. This implementation does nothing.
- (void)windowWillClose;

// The prefs panel calls this before another tab gets selected.
- (void)willDeselectTab;

- (void)resizeWindowForCurrentTabAnimated:(BOOL)animated;

// Override this if you have a tab view.
- (NSTabView * _Nullable)tabView;
- (CGFloat)minimumWidth;
- (void)saveDeferredUpdates;

- (BOOL)keyHasSyntheticGetter:(NSString *)key;
- (BOOL)keyHasSyntheticSetter:(NSString *)key;
- (id _Nullable)syntheticObjectForKey:(NSString *)key;
- (void)setSyntheticValue:(id)value forKey:(NSString *)key;
- (void)updateNonDefaultIndicatorVisibleForInfo:(PreferenceInfo *)info;
- (void)updateNonDefaultIndicators;
- (NSArray<iTermSetting *> *)allSettingsWithPathComponents:(NSArray<NSString *> *)pathComponents;
- (BOOL)hasControlWithKey:(NSString *)key;
- (BOOL)tryToggleControlWithKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
