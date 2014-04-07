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

// View controllers for tabs in the Preferences dialog inherit from this class. Consider it
// abstract. The pattern is to call -defineControl:key:type: in -awakeFromNib for each control.
// In IB, assign all controls the -settingChanged: selector, and for text fields, make your view
// controller the delegate.
@interface iTermPreferencesBaseViewController : NSViewController

#pragma mark - Core Methods

// Bind a preference control to a key defined in iTermPreferences.
- (PreferenceInfo *)defineControl:(NSControl *)control
                              key:(NSString *)key
                             type:(PreferenceInfoType)type;

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

@end
