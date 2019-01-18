//
//  iTermAdvancedSettingsController.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermAdvancedSettingsViewController.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSApplication+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSTextField+iTerm.h"
#import <objc/runtime.h>

static char iTermAdvancedSettingsTableKey;

@interface iTermTableViewTextField : NSTextField
@property (nonatomic, strong) NSAttributedString *regularAttributedString;
@property (nonatomic, strong) NSAttributedString *selectedAttributedString;
@end

@implementation iTermTableViewTextField

- (BOOL)becomeFirstResponder {
    if (@available(macOS 10.14, *)) {
        self.textColor = [NSColor labelColor];
    } else {
        self.textColor = [NSColor blackColor];
    }
    return YES;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    if (@available(macOS 10.14, *)) {
        switch (backgroundStyle) {
            case NSBackgroundStyleNormal:
                self.textColor = [NSColor labelColor];
                if (self.regularAttributedString) {
                    self.attributedStringValue = self.regularAttributedString;
                }
                break;
            case NSBackgroundStyleEmphasized:
                self.textColor = [NSColor labelColor];
                if (self.selectedAttributedString) {
                    self.attributedStringValue = self.selectedAttributedString;
                }
                break;

            case NSBackgroundStyleRaised:
            case NSBackgroundStyleLowered:
                break;
        }
        return;
    }
    if (self.textFieldIsFirstResponder) {
        self.textColor = [NSColor blackColor];
        if (self.regularAttributedString) {
            self.attributedStringValue = self.regularAttributedString;
        }
        return;
    }
    switch (backgroundStyle) {
        case NSBackgroundStyleLight:
            self.textColor = [NSColor blackColor];
            if (self.regularAttributedString) {
                self.attributedStringValue = self.regularAttributedString;
            }
            break;
        case NSBackgroundStyleDark:
            if (self.selectedAttributedString) {
                self.attributedStringValue = self.selectedAttributedString;
            }
            self.textColor = [NSColor whiteColor];
            break;

        case NSBackgroundStyleRaised:
        case NSBackgroundStyleLowered:
            break;
    }
}

@end

@interface iTermTableViewTextFieldWrapper : NSView
@end

@implementation iTermTableViewTextFieldWrapper

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle {
    iTermTableViewTextField *textField = self.subviews.firstObject;
    [textField setBackgroundStyle:backgroundStyle];
}

@end

@interface NSDictionary (AdvancedSettings)
- (iTermAdvancedSettingType)advancedSettingType;
- (NSComparisonResult)compareAdvancedSettingDicts:(NSDictionary *)other;
@end

@implementation NSDictionary (AdvancedSettings)

- (iTermAdvancedSettingType)advancedSettingType {
    return (iTermAdvancedSettingType)[[self objectForKey:kAdvancedSettingType] intValue];
}

- (NSComparisonResult)compareAdvancedSettingDicts:(NSDictionary *)other {
    return [self[kAdvancedSettingDescription] compare:other[kAdvancedSettingDescription]];
}

@end

static NSDictionary *gIntrospection;

@interface iTermAdvancedSettingsViewController()<NSTextFieldDelegate>
@end

@implementation iTermAdvancedSettingsViewController {
    IBOutlet NSTableColumn *_settingColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSTableView *_tableView;

    NSArray *_filteredAdvancedSettings;
}

+ (NSDictionary *)settingsDictionary {
    static NSDictionary *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *temp = [NSMutableDictionary dictionary];
        for (NSDictionary *setting in [self advancedSettings]) {
            temp[setting[kAdvancedSettingIdentifier]] = setting;
        }
        settings = temp;
    });
    return settings;
}

+ (NSArray *)sortedAdvancedSettings {
    static NSArray *sortedAdvancedSettings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *advancedSettings = [self advancedSettings];
        sortedAdvancedSettings = [advancedSettings sortedArrayUsingSelector:@selector(compareAdvancedSettingDicts:)];
    });
   return sortedAdvancedSettings;
}

+ (NSArray *)groupedSettingsArrayFromSortedArray:(NSArray *)sorted {
    NSString *previousCategory = nil;
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *dict in sorted) {
        NSString *description = dict[kAdvancedSettingDescription];
        NSInteger colon = [description rangeOfString:@":"].location;
        NSString *thisCategory = [description substringToIndex:colon];
        NSString *remainder = [description substringFromIndex:colon + 2];
        if (![thisCategory isEqualToString:previousCategory]) {
            previousCategory = [thisCategory copy];
            [result addObject:thisCategory];
        }
        NSMutableDictionary *temp = [dict mutableCopy];
        temp[kAdvancedSettingDescription] = remainder;
        [result addObject:temp];
    }
    return result;
}

+ (NSArray *)advancedSettings {
    static NSMutableArray *settings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        settings = [NSMutableArray array];
        [iTermAdvancedSettingsModel enumerateDictionaries:^(NSDictionary *dict) {
            [settings addObject:dict];
        }];
    });

    return settings;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // For reasons I don't understand the tableview outlives this view by a small amount.
    // To reproduce, select a row in advanced prefs. Switch to the profiles tab. Press esc to close
    // the prefs window. Doesn't reproduce all the time.
    _tableView.delegate = nil;
    _tableView.dataSource = nil;
}

- (void)awakeFromNib {
    [_tableView setFloatsGroupRows:YES];
    [_tableView setGridColor:[NSColor clearColor]];
    [_tableView setGridStyleMask:NSTableViewGridNone];
    [_tableView setIntercellSpacing:NSMakeSize(0, 0)];
    if (@available(macOS 10.14, *)) { } else {
        [_tableView setBackgroundColor:[NSColor whiteColor]];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(advancedSettingsDidChange:)
                                                 name:iTermAdvancedSettingsDidChange
                                               object:nil];
}

- (NSMutableAttributedString *)attributedStringForString:(NSString *)string
                                                    size:(CGFloat)size
                                               topMargin:(CGFloat)topMargin
                                                selected:(BOOL)selected
                                                    bold:(BOOL)bold {
    NSDictionary *spacerAttributes = @{ NSFontAttributeName: [NSFont systemFontOfSize:topMargin] };
    NSAttributedString *topSpacer = [[NSAttributedString alloc] initWithString:@"\n"
                                                                    attributes:spacerAttributes];
    NSColor *textColor;
    if (@available(macOS 10.14, *)) {
        textColor = [NSColor labelColor];
    } else {
        textColor = (selected && self.view.window.isKeyWindow) ? [NSColor whiteColor] : [NSColor blackColor];
    }
    NSDictionary *attributes =
        @{ NSFontAttributeName: bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size],
           NSForegroundColorAttributeName: textColor };
    NSAttributedString *title = [[NSAttributedString alloc] initWithString:string
                                                                attributes:attributes];
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:topSpacer];
    [result appendAttributedString:title];
    return result;
}

- (NSAttributedString *)attributedStringForGroupNamed:(NSString *)groupName {
    return [self attributedStringForString:groupName size:20 topMargin:8 selected:NO bold:YES];
}

- (iTermTableViewTextField *)viewForImmutableAttributedString:(NSAttributedString *)attributedString
                                                     selected:(NSAttributedString *)selectedAttributedString{
    iTermTableViewTextField *textField = [_tableView makeViewWithIdentifier:@"attributedstring" owner:self] ?: [[iTermTableViewTextField alloc] init];
    textField.delegate = nil;
    textField.identifier = @"attributedstring";
    textField.usesSingleLineMode = NO;
    textField.regularAttributedString = attributedString;
    textField.selectedAttributedString = selectedAttributedString;
    textField.bezeled = NO;
    textField.editable = NO;
    textField.selectable = NO;
    textField.drawsBackground = NO;
    return textField;
}

- (NSView *)onOffViewWithValue:(BOOL)on row:(int)row {
    NSPopUpButton *button = [_tableView makeViewWithIdentifier:@"onoff" owner:self] ?: [[NSPopUpButton alloc] init];
    [button it_setAssociatedObject:@(row) forKey:&iTermAdvancedSettingsTableKey];
    [button setTarget:self];
    [button setAction:@selector(toggleOnOff:)];
    button.identifier = @"onoff";
    [button.menu removeAllItems];
    [button.menu addItemWithTitle:@"No" action:nil keyEquivalent:@""];
    [button.menu addItemWithTitle:@"Yes" action:nil keyEquivalent:@""];
    [button selectItemAtIndex:on ? 1 : 0];
    return button;
}

- (void)toggleOnOff:(NSPopUpButton *)sender {
    const int row = [[sender it_associatedObjectForKey:&iTermAdvancedSettingsTableKey] intValue];
    const NSInteger index = sender.indexOfSelectedItem;
    const BOOL value = index == 0 ? NO : YES;
    NSArray *settings = [self filteredAdvancedSettings];
    NSDictionary *dict = settings[row];
    NSString *identifier = dict[kAdvancedSettingIdentifier];
    [[NSUserDefaults standardUserDefaults] setBool:value
                                            forKey:identifier];
}

- (id)objectForRow:(int)row {
    NSArray *settings = [self filteredAdvancedSettings];
    NSDictionary *dict = settings[row];
    NSString *identifier = dict[kAdvancedSettingIdentifier];
    return [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
}

// 0 = unknown, 1 = off, 2 = on
- (NSView *)tristateViewWithValue:(int)tristate row:(int)row {
    NSPopUpButton *button = [_tableView makeViewWithIdentifier:@"tristate" owner:self] ?: [[NSPopUpButton alloc] init];
    [button it_setAssociatedObject:@(row) forKey:&iTermAdvancedSettingsTableKey];
    [button setTarget:self];
    [button setAction:@selector(toggleTristate:)];
    button.identifier = @"tristate";
    [button.menu removeAllItems];
    [button.menu addItemWithTitle:@"Unspecified" action:nil keyEquivalent:@""];
    [button.menu addItemWithTitle:@"No" action:nil keyEquivalent:@""];
    [button.menu addItemWithTitle:@"Yes" action:nil keyEquivalent:@""];

    NSNumber *value = [self objectForRow:row];
    if (!value) {
        [button selectItemAtIndex:0];
    } else {
        [button selectItemAtIndex:value.boolValue ? 2 : 1];
    }
    return button;
}

- (void)toggleTristate:(NSPopUpButton *)sender {
    const int row = [[sender it_associatedObjectForKey:&iTermAdvancedSettingsTableKey] intValue];
    const NSInteger value = sender.indexOfSelectedItem;
    NSArray *settings = [self filteredAdvancedSettings];
    NSDictionary *dict = settings[row];
    NSString *identifier = dict[kAdvancedSettingIdentifier];
    if (value == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:identifier];
    } else {
        [[NSUserDefaults standardUserDefaults] setBool:value == 2
                                                forKey:identifier];
    }
}

- (iTermTableViewTextFieldWrapper *)viewForMutableString:(NSString *)string row:(int)row {
    iTermTableViewTextFieldWrapper *wrapper = [_tableView makeViewWithIdentifier:@"mutablestring" owner:self] ?: [[iTermTableViewTextFieldWrapper alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
    wrapper.frame = NSMakeRect(0, 0, 100, 100);
    iTermTableViewTextField *textField = wrapper.subviews.firstObject ?: [[iTermTableViewTextField alloc] init];
    [wrapper addSubview:textField];
    [textField it_setAssociatedObject:@(row) forKey:&iTermAdvancedSettingsTableKey];
    textField.delegate = self;
    textField.identifier = @"mutablestring";
    textField.editable = YES;
    textField.selectable = YES;
    textField.stringValue = string;
    textField.bezeled = NO;
    textField.drawsBackground = NO;
    textField.usesSingleLineMode = YES;
    [textField sizeToFit];
    textField.frame = NSMakeRect(0, (wrapper.frame.size.height - textField.frame.size.height) / 2.0, wrapper.frame.size.width, textField.frame.size.height);
    wrapper.autoresizesSubviews = YES;
    textField.autoresizingMask = (NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin);
    return wrapper;
}

- (BOOL)description:(NSString *)description matchesQuery:(NSArray *)queryWords {
    for (NSString *word in queryWords) {
        if (word.length == 0) {
            continue;
        }
        if ([description rangeOfString:word options:NSCaseInsensitiveSearch].location == NSNotFound) {
            return NO;
        }
    }
    return YES;
}

- (NSArray *)filteredAdvancedSettings {
    if (!_filteredAdvancedSettings) {
        NSArray *settings;

        if (_searchField.stringValue.length == 0) {
            settings = [[self class] sortedAdvancedSettings];
        } else {
            NSMutableArray *result = [NSMutableArray array];
            NSArray *parts = [_searchField.stringValue componentsSeparatedByString:@" "];
            NSArray *sortedSettings = [[self class] sortedAdvancedSettings];
            for (NSDictionary *dict in sortedSettings) {
                NSString *description = dict[kAdvancedSettingDescription];
                if ([self description:description matchesQuery:parts]) {
                    [result addObject:dict];
                }
            }

            settings = result;
        }

        _filteredAdvancedSettings = [[self class] groupedSettingsArrayFromSortedArray:settings];
    }

    return _filteredAdvancedSettings;
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    [_tableView reloadData];
}

#pragma mark - NSTableViewDelegate

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        return [[self attributedStringForGroupNamed:obj] size].height + 14;
    } else {
        NSAttributedString *attributedString = [self attributedStringForSettingAtRow:row selected:NO];
        CGFloat height = [attributedString heightForWidth:tableView.tableColumns[0].width] + 8;
        return MAX(30, height);
    }
}

- (NSAttributedString *)attributedStringForSettingWithName:(NSString *)description
                                                  subtitle:(NSString *)subtitle
                                                  selected:(BOOL)selected {
    NSMutableAttributedString *attributedDescription =
    [self attributedStringForString:description
                               size:[NSFont systemFontSize]
                          topMargin:2
                           selected:selected
                               bold:NO];
    if (subtitle) {
        NSColor *color;
        if (@available(macOS 10.14, *)) {
            color = [NSColor secondaryLabelColor];
        } else {
            color = (selected && self.view.window.isKeyWindow) ? [NSColor whiteColor] : [NSColor grayColor];
        }
        NSDictionary *attributes = @{ NSForegroundColorAttributeName: color,
                                      NSFontAttributeName: [NSFont systemFontOfSize:11] };
        NSAttributedString *attributedSubtitle =
        [[NSAttributedString alloc] initWithString:subtitle
                                        attributes:attributes];
        [attributedDescription appendAttributedString:attributedSubtitle];
    }
    return attributedDescription;
}

- (NSAttributedString *)attributedStringForSettingAtRow:(NSInteger)row selected:(BOOL)selected {
    NSArray *settings = [self filteredAdvancedSettings];
    NSString *description = settings[row][kAdvancedSettingDescription];
    NSUInteger newline = [description rangeOfString:@"\n"].location;
    NSString *subtitle = nil;
    if (newline != NSNotFound) {
        subtitle = [description substringFromIndex:newline];
        description = [description substringToIndex:newline];
    }
    return [self attributedStringForSettingWithName:description subtitle:subtitle selected:selected];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        return [self viewForImmutableAttributedString:[self attributedStringForGroupNamed:obj]
                                             selected:[self attributedStringForGroupNamed:obj]];
    }

    if (tableColumn == _settingColumn) {

        iTermTableViewTextField *textField = [self viewForImmutableAttributedString:[self attributedStringForSettingAtRow:row selected:NO]
                                                                           selected:[self attributedStringForSettingAtRow:row selected:YES]];
        NSTableRowView *rowView = [tableView rowViewAtRow:row makeIfNecessary:NO];
        if (rowView) {
            // An explicit call to rowViewAtRow:makeIfNecessary:YES as in
            // -selectRowIndex: is needed for this to be initialized correctly
            // if the background style is not default. If there's no rowView at
            // the time this is called, the backgroundStyle never gets initialized.
            // I think I'm going to become a farmer.
            textField.backgroundStyle = [rowView interiorBackgroundStyle];
        }
        return textField;
    } else if (tableColumn == _valueColumn) {
        NSDictionary *dict = settings[row];
        NSString *identifier = dict[kAdvancedSettingIdentifier];
        NSObject *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
        if (!value) {
            value = dict[kAdvancedSettingDefaultValue];
        }
        switch ([dict advancedSettingType]) {
            case kiTermAdvancedSettingTypeBoolean: {
                NSNumber *n = (NSNumber *)value;
                return [self onOffViewWithValue:n.boolValue row:row];
            }
            case kiTermAdvancedSettingTypeOptionalBoolean: {
                int tristate;
                if ([value isKindOfClass:[NSNull class]]) {
                    tristate = 0;
                } else if (![(NSNumber *)value boolValue]) {
                    tristate = 1;
                } else {
                    tristate = 2;
                }
                return [self tristateViewWithValue:tristate row:row];
            }

            case kiTermAdvancedSettingTypeFloat:
            case kiTermAdvancedSettingTypeInteger: {
                iTermTableViewTextFieldWrapper *wrapper = [self viewForMutableString:[NSString stringWithFormat:@"%@", value] row:row];
                NSTableRowView *rowView = [tableView rowViewAtRow:row makeIfNecessary:NO];
                if (rowView) {
                    wrapper.backgroundStyle = [rowView interiorBackgroundStyle];
                }
                return wrapper;
            }

            case kiTermAdvancedSettingTypeString: {
                iTermTableViewTextFieldWrapper *wrapper = [self viewForMutableString:(NSString *)value row:row];
                NSTableRowView *rowView = [tableView rowViewAtRow:row makeIfNecessary:NO];
                if (rowView) {
                    wrapper.backgroundStyle = [rowView interiorBackgroundStyle];
                }
                return wrapper;
            }
        }
    } else {
        return nil;
    }
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [[self filteredAdvancedSettings] count];
}


- (BOOL)tableView:(NSTableView *)aTableView
      shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[rowIndex];
    if ([obj isKindOfClass:[NSString class]]) {
        return NO;
    }

    return aTableColumn == _valueColumn;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    return ([obj isKindOfClass:[NSString class]]);
}

#pragma mark - NSControl Delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == _searchField) {
        _filteredAdvancedSettings = nil;
        [_tableView reloadData];
    } else {
        NSTextField *textField = aNotification.object;
        NSNumber *associatedObject = [textField it_associatedObjectForKey:&iTermAdvancedSettingsTableKey];
        if (!associatedObject) {
            return;
        }
        const int row = [associatedObject intValue];
        NSString *string = textField.stringValue;
        NSArray *settings = [self filteredAdvancedSettings];
        NSDictionary *dict = settings[row];
        NSString *identifier = dict[kAdvancedSettingIdentifier];
        switch ([dict advancedSettingType]) {
            case kiTermAdvancedSettingTypeBoolean:
            case kiTermAdvancedSettingTypeOptionalBoolean:
                assert(NO);
                break;

            case kiTermAdvancedSettingTypeFloat:
                [[NSUserDefaults standardUserDefaults] setFloat:string.floatValue
                                                         forKey:identifier];
                break;

            case kiTermAdvancedSettingTypeInteger:
                [[NSUserDefaults standardUserDefaults] setInteger:string.integerValue
                                                           forKey:identifier];
                break;

            case kiTermAdvancedSettingTypeString:
                [[NSUserDefaults standardUserDefaults] setObject:string
                                                          forKey:identifier];
                break;
        }
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if ([obj object] == _searchField) {
        return;
    }
    iTermTableViewTextField *textField = obj.object;
    NSNumber *associatedObject = [textField it_associatedObjectForKey:&iTermAdvancedSettingsTableKey];
    if (!associatedObject) {
        return;
    }
    const int row = [associatedObject intValue];
    NSString *string = textField.stringValue;
    NSArray *settings = [self filteredAdvancedSettings];
    NSDictionary *dict = settings[row];
    switch ([dict advancedSettingType]) {
        case kiTermAdvancedSettingTypeBoolean:
        case kiTermAdvancedSettingTypeOptionalBoolean:
            assert(NO);
            break;

        case kiTermAdvancedSettingTypeFloat:
            textField.stringValue = [NSString stringWithFormat:@"%@", @([string doubleValue])];
            break;

        case kiTermAdvancedSettingTypeInteger:
            textField.integerValue = string.integerValue;
            break;

        case kiTermAdvancedSettingTypeString:
            break;
    }

    NSTableRowView *rowView = [_tableView rowViewAtRow:row makeIfNecessary:NO];
    if (rowView) {
        textField.backgroundStyle = [rowView interiorBackgroundStyle];
    }
}

@end
