//
//  iTermAdvancedSettingsController.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermAdvancedSettingsController.h"

typedef enum {
    kiTermAdvancedSettingTypeBoolean,
    kiTermAdvancedSettingTypeInteger,
    kiTermAdvancedSettingTypeFloat
} iTermAdvancedSettingType;

static NSString *const kAdvancedSettingIdentifier = @"kAdvancedSettingIdentifier";
static NSString *const kAdvancedSettingType = @"kAdvancedSettingType";
static NSString *const kAdvancedSettingDefaultValue = @"kAdvancedSettingDefaultValue";
static NSString *const kAdvancedSettingDescription = @"kAdvancedSettingDescription";

NSString *const kAdvancedSettingIdentiferUseUnevenTabs = @"UseUnevenTabs";
NSString *const kAdvancedSettingIdentiferMinTabWidth = @"MinTabWidth";
NSString *const kAdvancedSettingIdentiferMinCompactTabWidth = @"MinCompactTabWidth";
NSString *const kAdvancedSettingIdentiferOptimumTabWidth = @"OptimumTabWidth";
NSString *const kAdvancedSettingIdentiferAlternateMouseScroll = @"AlternateMouseScroll";
NSString *const kAdvancedSettingIdentiferTraditionalVisualBell = @"TraditionalVisualBell";

@interface NSDictionary (AdvancedSettings)
- (iTermAdvancedSettingType)advancedSettingType;
@end

@implementation NSDictionary (AdvancedSettings)

- (iTermAdvancedSettingType)advancedSettingType {
    return (iTermAdvancedSettingType)[[self objectForKey:kAdvancedSettingType] intValue];
}

@end

@implementation iTermAdvancedSettingsController {
    IBOutlet NSTableColumn *_settingColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSTableView *_tableView;
}

+ (BOOL)boolForIdentifier:(NSString *)identifier {
    NSDictionary *dict = [self settingsDictionary][identifier];
    assert([dict advancedSettingType] == kiTermAdvancedSettingTypeBoolean);
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return [dict[kAdvancedSettingDefaultValue] boolValue];
    } else {
        return [value boolValue];
    }
}

+ (int)intForIdentifier:(NSString *)identifier {
    NSDictionary *dict = [self settingsDictionary][identifier];
    assert([dict advancedSettingType] == kiTermAdvancedSettingTypeInteger);
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return [dict[kAdvancedSettingDefaultValue] intValue];
    } else {
        return [value intValue];
    }
}

+ (double)floatForIdentifier:(NSString *)identifier {
    NSDictionary *dict = [self settingsDictionary][identifier];
    assert([dict advancedSettingType] == kiTermAdvancedSettingTypeFloat);
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return [dict[kAdvancedSettingDefaultValue] doubleValue];
    } else {
        return [value doubleValue];
    }
}

+ (NSDictionary *)settingsDictionary {
    static NSDictionary *settings;
    if (!settings) {
        NSMutableDictionary *temp = [NSMutableDictionary dictionary];
        for (NSDictionary *setting in [self advancedSettings]) {
            temp[setting[kAdvancedSettingIdentifier]] = setting;
        }
        settings = [temp retain];
    }
    return settings;
}

+ (NSArray *)advancedSettings {
    static NSArray *settings;
    if (!settings) {
        settings = @[
            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferUseUnevenTabs,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeBoolean),
               kAdvancedSettingDefaultValue: @NO,
               kAdvancedSettingDescription: @"Uneven tab widths allowed" },

            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferMinTabWidth,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeInteger),
               kAdvancedSettingDefaultValue: @75,
               kAdvancedSettingDescription: @"Minimum tab width" },

            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferMinCompactTabWidth,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeInteger),
               kAdvancedSettingDefaultValue: @60,
               kAdvancedSettingDescription: @"Minimum tab width for tabs without close button or number" },

            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferOptimumTabWidth,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeInteger),
               kAdvancedSettingDefaultValue: @175,
               kAdvancedSettingDescription: @"Preferred tab width" },

            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferAlternateMouseScroll,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeBoolean),
               kAdvancedSettingDefaultValue: @NO,
               kAdvancedSettingDescription: @"Scroll wheel sends arrow keys in alternate screen mode" },

            @{ kAdvancedSettingIdentifier: kAdvancedSettingIdentiferTraditionalVisualBell,
               kAdvancedSettingType: @(kiTermAdvancedSettingTypeBoolean),
               kAdvancedSettingDefaultValue: @NO,
               kAdvancedSettingDescription: @"Visual bell flashes the whole screen, not just a bell icon" },


            ];
        [settings retain];
    }
    return settings;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    if (tableColumn == _settingColumn) {
        return settings[row][kAdvancedSettingDescription];
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
                if ([n boolValue]) {
                    return @1;
                } else {
                    return @0;
                }
            }
            case kiTermAdvancedSettingTypeFloat:
            case kiTermAdvancedSettingTypeInteger:
                return [NSString stringWithFormat:@"%@", value];
        }
    } else {
        return nil;
    }
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
    if (_searchField.stringValue.length == 0) {
        return [[self class] advancedSettings];
    } else {
        NSMutableArray *result = [NSMutableArray array];
        NSArray *parts = [_searchField.stringValue componentsSeparatedByString:@" "];
        for (NSDictionary *dict in [[self class] advancedSettings]) {
            NSString *description = dict[kAdvancedSettingDescription];
            if ([self description:description matchesQuery:parts]) {
                [result addObject:dict];
            }
        }
        return result;
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [[self filteredAdvancedSettings] count];
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
                       row:(NSInteger)row {
    if (tableColumn == _valueColumn) {
        NSArray *settings = [self filteredAdvancedSettings];
        NSDictionary *dict = settings[row];
        switch ([dict advancedSettingType]) {
            case kiTermAdvancedSettingTypeBoolean: {
                NSPopUpButtonCell *cell =
                        [[[NSPopUpButtonCell alloc] initTextCell:@"No" pullsDown:NO] autorelease];
                [cell addItemWithTitle:@"No"];
                [cell addItemWithTitle:@"Yes"];
                [cell setBordered:NO];
                return cell;
            }
            case kiTermAdvancedSettingTypeFloat:
            case kiTermAdvancedSettingTypeInteger: {
                NSTextFieldCell *cell = [[[NSTextFieldCell alloc] initTextCell:@"scalar"] autorelease];
                [cell setPlaceholderString:@"Value"];
                [cell setEditable:YES];
                [cell setTruncatesLastVisibleLine:YES];
                [cell setLineBreakMode:NSLineBreakByTruncatingTail];
                return cell;
            }
        }
    }
    return nil;
}

- (BOOL)tableView:(NSTableView *)aTableView
      shouldEditTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex {
    return aTableColumn == _valueColumn;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (tableColumn == _valueColumn) {
        NSArray *settings = [self filteredAdvancedSettings];
        NSDictionary *dict = settings[row];
        NSString *identifier = dict[kAdvancedSettingIdentifier];
        NSObject *value = nil;
        switch ([dict advancedSettingType]) {
            case kiTermAdvancedSettingTypeBoolean:
                [[NSUserDefaults standardUserDefaults] setBool:!![anObject intValue]
                                                        forKey:identifier];
                break;

            case kiTermAdvancedSettingTypeFloat:
                [[NSUserDefaults standardUserDefaults] setFloat:[anObject floatValue]
                                                        forKey:identifier];
                break;

            case kiTermAdvancedSettingTypeInteger:
                [[NSUserDefaults standardUserDefaults] setInteger:[anObject integerValue]
                                                           forKey:identifier];
        }
    }
}

#pragma mark - NSControl Delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    [_tableView reloadData];
}

@end
