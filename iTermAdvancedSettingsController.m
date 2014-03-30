//
//  iTermAdvancedSettingsController.m
//  iTerm
//
//  Created by George Nachman on 3/18/14.
//
//

#import "iTermAdvancedSettingsController.h"
#import "iTermSettingsModel.h"
#import <objc/runtime.h>

typedef enum {
    kiTermAdvancedSettingTypeBoolean,
    kiTermAdvancedSettingTypeInteger,
    kiTermAdvancedSettingTypeFloat,
    kiTermAdvancedSettingTypeString
} iTermAdvancedSettingType;

static NSString *const kAdvancedSettingIdentifier = @"kAdvancedSettingIdentifier";
static NSString *const kAdvancedSettingType = @"kAdvancedSettingType";
static NSString *const kAdvancedSettingDefaultValue = @"kAdvancedSettingDefaultValue";
static NSString *const kAdvancedSettingDescription = @"kAdvancedSettingDescription";

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

static BOOL gIntrospecting;
static NSDictionary *gIntrospection;

@implementation iTermAdvancedSettingsController {
    IBOutlet NSTableColumn *_settingColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSTableView *_tableView;
}

+ (BOOL)boolForIdentifier:(NSString *)identifier
             defaultValue:(BOOL)defaultValue
              description:(NSString *)description {
    if (gIntrospecting) {
        [gIntrospection autorelease];
        gIntrospection = [@{ kAdvancedSettingIdentifier: identifier,
                             kAdvancedSettingType: @(kiTermAdvancedSettingTypeBoolean),
                             kAdvancedSettingDefaultValue: @(defaultValue),
                             kAdvancedSettingDescription: description } retain];
        return defaultValue;
    }
    
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return defaultValue;
    } else {
        return [value boolValue];
    }
}

+ (int)intForIdentifier:(NSString *)identifier
           defaultValue:(int)defaultValue
            description:(NSString *)description {
    if (gIntrospecting) {
        [gIntrospection autorelease];
        gIntrospection = [@{ kAdvancedSettingIdentifier: identifier,
                             kAdvancedSettingType: @(kiTermAdvancedSettingTypeInteger),
                             kAdvancedSettingDefaultValue: @(defaultValue),
                             kAdvancedSettingDescription: description } retain];
        return defaultValue;
    }

    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return defaultValue;
    } else {
        return [value intValue];
    }
}

+ (double)floatForIdentifier:(NSString *)identifier
                defaultValue:(double)defaultValue
                 description:(NSString *)description {
    if (gIntrospecting) {
        [gIntrospection autorelease];
        gIntrospection = [@{ kAdvancedSettingIdentifier: identifier,
                             kAdvancedSettingType: @(kiTermAdvancedSettingTypeFloat),
                             kAdvancedSettingDefaultValue: @(defaultValue),
                             kAdvancedSettingDescription: description } retain];
        return defaultValue;
    }

    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return defaultValue;
    } else {
        return [value doubleValue];
    }
}

+ (NSString *)stringForIdentifier:(NSString *)identifier
                     defaultValue:(NSString *)defaultValue
                      description:(NSString *)description {
    if (gIntrospecting) {
        [gIntrospection autorelease];
        gIntrospection = [@{ kAdvancedSettingIdentifier: identifier,
                             kAdvancedSettingType: @(kiTermAdvancedSettingTypeString),
                             kAdvancedSettingDefaultValue: defaultValue,
                             kAdvancedSettingDescription: description } retain];
        return defaultValue;
    }

    NSString *value = [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
    if (!value) {
        return defaultValue;
    } else {
        return value;
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

+ (NSArray *)sortedAdvancedSettings {
    return [[self advancedSettings] sortedArrayUsingSelector:@selector(compareAdvancedSettingDicts:)];
}

+ (NSArray *)advancedSettings {
    static NSMutableArray *settings;
    if (!settings) {
        settings = [NSMutableArray array];
        NSArray *internalMethods = @[ @"initialize", @"load" ];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(object_getClass([iTermSettingsModel class]), &methodCount);
        gIntrospecting = YES;
        for (int i = 0; i < methodCount; i++) {
            SEL name = method_getName(methods[i]);
            NSString *stringName = NSStringFromSelector(name);
            if (![internalMethods containsObject:stringName]) {
                [iTermSettingsModel performSelector:name withObject:nil];
                assert(gIntrospection != nil);
                [settings addObject:gIntrospection];
                [gIntrospection release];
                gIntrospection = nil;
            }
        }
        gIntrospecting = NO;
        free(methods);

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
                
            case kiTermAdvancedSettingTypeString:
                return value;
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
        return [[self class] sortedAdvancedSettings];
    } else {
        NSMutableArray *result = [NSMutableArray array];
        NSArray *parts = [_searchField.stringValue componentsSeparatedByString:@" "];
        for (NSDictionary *dict in [[self class] sortedAdvancedSettings]) {
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
            case kiTermAdvancedSettingTypeString:
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
                break;

            case kiTermAdvancedSettingTypeString:
                [[NSUserDefaults standardUserDefaults] setObject:anObject forKey:identifier];
                break;
        }
    }
}

#pragma mark - NSControl Delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == _searchField) {
        [_tableView reloadData];
    }
}

@end
