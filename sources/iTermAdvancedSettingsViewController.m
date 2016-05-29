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
#import <objc/runtime.h>

NSString *const iTermAdvancedSettingsDidChange = @"iTermAdvancedSettingsDidChange";

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

@implementation iTermAdvancedSettingsViewController {
    IBOutlet NSTableColumn *_settingColumn;
    IBOutlet NSTableColumn *_valueColumn;
    IBOutlet NSSearchField *_searchField;
    IBOutlet NSTableView *_tableView;

    NSArray *_filteredAdvancedSettings;
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

    static BOOL testing;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        testing = [[NSApplication sharedApplication] isRunningUnitTests];
    });
    if (testing) {
        NSDictionary *overrides = @{ @"RunJobsInServers": @NO };
        if (overrides[identifier]) {
            return [overrides[identifier] boolValue];
        }
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
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary *temp = [NSMutableDictionary dictionary];
        for (NSDictionary *setting in [self advancedSettings]) {
            temp[setting[kAdvancedSettingIdentifier]] = setting;
        }
        settings = [temp retain];
    });
    return settings;
}

+ (NSArray *)sortedAdvancedSettings {
    static NSArray *sortedAdvancedSettings;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *advancedSettings = [self advancedSettings];
        sortedAdvancedSettings = [advancedSettings sortedArrayUsingSelector:@selector(compareAdvancedSettingDicts:)];
        [sortedAdvancedSettings retain];
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
            previousCategory = [[thisCategory copy] autorelease];
            [result addObject:thisCategory];
        }
        NSMutableDictionary *temp = [[dict mutableCopy] autorelease];
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
        NSArray *internalMethods = @[ @"initialize", @"load" ];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(object_getClass([iTermAdvancedSettingsModel class]), &methodCount);
        gIntrospecting = YES;
        for (int i = 0; i < methodCount; i++) {
            SEL name = method_getName(methods[i]);
            NSString *stringName = NSStringFromSelector(name);
            // Ignore selectors ending with : because they are setters.
            if (![internalMethods containsObject:stringName] && ![stringName hasSuffix:@":"]) {
                [iTermAdvancedSettingsModel performSelector:name withObject:nil];
                assert(gIntrospection != nil);
                [settings addObject:gIntrospection];
                [gIntrospection release];
                gIntrospection = nil;
            }
        }
        gIntrospecting = NO;
        free(methods);

        [settings retain];
    });

    return settings;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_filteredAdvancedSettings release];
    [super dealloc];
}

- (void)awakeFromNib {
    [_tableView setFloatsGroupRows:YES];
    [_tableView setGridColor:[NSColor clearColor]];
    [_tableView setGridStyleMask:NSTableViewGridNone];
    [_tableView setIntercellSpacing:NSMakeSize(0, 0)];
    [_tableView setBackgroundColor:[NSColor whiteColor]];

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
    NSAttributedString *topSpacer = [[[NSAttributedString alloc] initWithString:@"\n"
                                                                     attributes:spacerAttributes] autorelease];
    NSDictionary *attributes =
        @{ NSFontAttributeName: bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size],
           NSForegroundColorAttributeName: (selected && self.view.window.isKeyWindow) ? [NSColor whiteColor] : [NSColor blackColor] };
    NSAttributedString *title = [[[NSAttributedString alloc] initWithString:string
                                                                 attributes:attributes] autorelease];
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    [result appendAttributedString:topSpacer];
    [result appendAttributedString:title];
    return result;
}

- (NSAttributedString *)attributedStringForGroupNamed:(NSString *)groupName {
    return [self attributedStringForString:groupName size:20 topMargin:8 selected:NO bold:YES];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        return [[self attributedStringForGroupNamed:obj] size].height;
    } else {
        NSCell *cell = [tableView preparedCellAtColumn:0 row:row];
        [cell setWraps:YES];
        NSTableColumn *column = [[tableView tableColumns] firstObject];
        NSRect constrainedBounds = NSMakeRect(0, 0, column.width, CGFLOAT_MAX);
        NSSize naturalSize = [cell cellSizeForBounds:constrainedBounds];
        return naturalSize.height + 4;
    }
}

- (void)tableView:(NSTableView *)tableView
  willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    [cell setBackgroundColor:[NSColor whiteColor]];
    if ([obj isKindOfClass:[NSString class]]) {
        [cell setDrawsBackground:YES];
    } else {
        [cell setWraps:YES];
    }
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    if ([obj isKindOfClass:[NSString class]]) {
        if (tableColumn == _settingColumn) {
            return [self attributedStringForGroupNamed:obj];
        } else {
            return nil;
        }
    }

    if (tableColumn == _settingColumn) {
        NSString *description = settings[row][kAdvancedSettingDescription];
        NSUInteger newline = [description rangeOfString:@"\n"].location;
        NSString *subtitle = nil;
        if (newline != NSNotFound) {
            subtitle = [description substringFromIndex:newline];
            description = [description substringToIndex:newline];
        }

        NSMutableAttributedString *attributedDescription =
            [self attributedStringForString:description
                                       size:[NSFont systemFontSize]
                                  topMargin:2
                                   selected:tableView.selectedRow == row
                                       bold:NO];
        if (subtitle) {
            NSColor *color = (tableView.selectedRow == row && self.view.window.isKeyWindow) ? [NSColor whiteColor] : [NSColor grayColor];
            NSDictionary *attributes = @{ NSForegroundColorAttributeName: color,
                                          NSFontAttributeName: [NSFont systemFontOfSize:11] };
            NSAttributedString *attributedSubtitle =
                [[[NSAttributedString alloc] initWithString:subtitle
                                                 attributes:attributes] autorelease];
            [attributedDescription appendAttributedString:attributedSubtitle];
        }
        return attributedDescription;
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

        _filteredAdvancedSettings = [[[self class] groupedSettingsArrayFromSortedArray:settings] retain];
    }

    return _filteredAdvancedSettings;
}

- (void)advancedSettingsDidChange:(NSNotification *)notification {
    [_tableView reloadData];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [[self filteredAdvancedSettings] count];
}

- (NSCell *)tableView:(NSTableView *)tableView
    dataCellForTableColumn:(NSTableColumn *)tableColumn
                       row:(NSInteger)row {
    if (tableColumn == _valueColumn) {
        NSArray *settings = [self filteredAdvancedSettings];
        id obj = settings[row];
        if ([obj isKindOfClass:[NSString class]]) {
            return nil;
        }

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
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[rowIndex];
    if ([obj isKindOfClass:[NSString class]]) {
        return NO;
    }

    return aTableColumn == _valueColumn;
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (tableColumn == _valueColumn) {
        NSArray *settings = [self filteredAdvancedSettings];
        id obj = settings[row];
        if ([obj isKindOfClass:[NSString class]]) {
            return;
        }
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

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row {
    NSArray *settings = [self filteredAdvancedSettings];
    id obj = settings[row];
    return ([obj isKindOfClass:[NSString class]]);
}

#pragma mark - NSControl Delegate

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if ([aNotification object] == _searchField) {
        [_filteredAdvancedSettings release];
        _filteredAdvancedSettings = nil;
        [_tableView reloadData];
    }
}

@end
