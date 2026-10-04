//
//  iTermNumberOfSpacesAccessoryViewController.m
//  iTerm2
//
//  Created by George Nachman on 11/30/14.
//
//

#import "iTermNumberOfSpacesAccessoryViewController.h"
#import "iTermPreferences.h"
#import "iTermWarning.h"

// The range the text field itself enforces; see -controlTextDidChange:.
static const NSInteger iTermNumberOfSpacesMinimum = 0;
static const NSInteger iTermNumberOfSpacesMaximum = 100;

@interface iTermNumberOfSpacesAccessoryViewController()<NSControlTextEditingDelegate>
@property(nonatomic, readwrite) int numberOfSpaces;
@end

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

- (iTermWarningRemoteInput *)remoteInput {
    // Loads the view, so the outlets and the stored value are set.
    NSView *view = self.view;
    // The field's own label ("Tab size in spaces:"), which is already localized with the nib.
    NSString *label = nil;
    for (NSView *subview in view.subviews) {
        NSTextField *candidate = [subview isKindOfClass:[NSTextField class]] ? (NSTextField *)subview : nil;
        if (candidate && candidate != _textField && !candidate.isEditable) {
            label = candidate.stringValue;
            break;
        }
    }
    __weak __typeof(self) weakSelf = self;
    // Localization unneeded: the identifier is not shown.
    return [iTermWarningRemoteInput integerInputWithIdentifier:@"numberOfSpaces"
                                                         label:label
                                                       minimum:iTermNumberOfSpacesMinimum
                                                       maximum:iTermNumberOfSpacesMaximum
                                                        getter:^NSInteger{
        return weakSelf.numberOfSpaces;
    }
                                                        setter:^(NSInteger value) {
        weakSelf.numberOfSpaces = (int)value;
    }];
}

#pragma mark - Actions

- (IBAction)stepperDidChange:(id)sender {
    _textField.integerValue = [sender integerValue];
    _numberOfSpaces = _textField.integerValue;
}

#pragma mark - NSTextField Delegate

- (void)controlTextDidChange:(NSNotification *)obj {
    _textField.integerValue = MAX(iTermNumberOfSpacesMinimum, MIN(iTermNumberOfSpacesMaximum, _textField.integerValue));
    _stepper.integerValue = _textField.integerValue;
    _numberOfSpaces = _textField.integerValue;
}


@end
