//
//  iTermNumberOfSpacesAccessoryViewController.m
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import "iTermNumberOfSpacesAccessoryViewController.h"
#import "iTermPreferences.h"

@implementation iTermNumberOfSpacesAccessoryViewController {
    int _numberOfSpaces;
    IBOutlet NSTextField *_textField;
    IBOutlet NSStepper *_stepper;
}

- (instancetype)init {
    return [super initWithNibName:@"NumberOfSpacesAccessoryView" bundle:[NSBundle bundleForClass:self.class]];
}

- (void)awakeFromNib {
    self.numberOfSpaces =
        [iTermPreferences intForKey:kPreferenceKeyPasteWarningNumberOfSpacesPerTab];
}

- (void)saveToUserDefaults {
    [iTermPreferences setInt:_numberOfSpaces forKey:kPreferenceKeyPasteWarningNumberOfSpacesPerTab];
}

- (void)setNumberOfSpaces:(int)numberOfSpaces {
    _numberOfSpaces = numberOfSpaces;
    _textField.integerValue = numberOfSpaces;
    _stepper.integerValue = numberOfSpaces;
}

#pragma mark - Actions

- (IBAction)stepperDidChange:(id)sender {
    _textField.integerValue = [sender integerValue];
    _numberOfSpaces = _textField.integerValue;
}

#pragma mark - NSTextField Delegate

- (void)controlTextDidChange:(NSNotification *)obj {
    _textField.integerValue = MAX(0, MIN(100, _textField.integerValue));
    _stepper.integerValue = _textField.integerValue;
    _numberOfSpaces = _textField.integerValue;
}


@end
