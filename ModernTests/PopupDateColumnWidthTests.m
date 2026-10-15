//
//  PopupDateColumnWidthTests.m
//  ModernTests
//
//  QA finding F-312: in German the Command History popup clipped its relative
//  dates (“Vor 12 Sekunde”) because the date column had a fixed width sized
//  for English. These give the popup the relative dates each shipped
//  language produces and check that the date column grows to fit them.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CommandHistoryPopup.h"

@interface PopupDateColumnWidthTestPopup : CommandHistoryPopupWindowController
@property(nonatomic, copy) NSArray<NSString *> *dates;
@end

@implementation PopupDateColumnWidthTestPopup

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return self.dates.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([column.identifier isEqualToString:@"date"]) {
        return self.dates[row];
    }
    return @"ls";
}

@end

@interface PopupDateColumnWidthTests : XCTestCase
@end

@implementation PopupDateColumnWidthTests

// What NSDateFormatter+Extras shows for a non-English UI, for a spread of
// ages.
- (NSArray<NSString *> *)relativeDatesForLanguage:(NSString *)language {
    NSRelativeDateTimeFormatter *formatter = [[NSRelativeDateTimeFormatter alloc] init];
    formatter.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;
    formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
    formatter.locale = [NSLocale localeWithLocaleIdentifier:language];
    NSDate *now = [NSDate date];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSNumber *age in @[ @12, @58, @(59 * 60), @(23 * 3600), @(5 * 86400), @(3 * 7 * 86400),
                             @(11 * 30 * 86400), @(5 * 365 * 86400) ]) {
        NSString *string = [formatter localizedStringForDate:[now dateByAddingTimeInterval:-age.doubleValue]
                                              relativeToDate:now];
        [result addObject:[string stringByReplacingCharactersInRange:NSMakeRange(0, 1)
                                                          withString:[[string substringToIndex:1] localizedUppercaseString]]];
    }
    return result;
}

- (NSTableView *)tableOf:(PopupDateColumnWidthTestPopup *)popup {
    NSTableView *table = [popup valueForKey:@"_tableView"];
    XCTAssertNotNil(table);
    return table;
}

- (void)testGermanSecondsNeedMoreThanTheNibWidth {
    // Guards the premise: the string QA saw clipped doesn't fit the column
    // the nib gives it.
    PopupDateColumnWidthTestPopup *popup = [[PopupDateColumnWidthTestPopup alloc] initForAutoComplete:NO];
    NSTableColumn *column = [[self tableOf:popup] tableColumnWithIdentifier:@"date"];
    NSCell *cell = [column.dataCell copy];
    cell.objectValue = [self relativeDatesForLanguage:@"de"][0];
    XCTAssertGreaterThan(ceil(cell.cellSize.width), column.width);
    [popup shutdown];
}

- (void)testDateColumnFitsEveryLanguage {
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        PopupDateColumnWidthTestPopup *popup = [[PopupDateColumnWidthTestPopup alloc] initForAutoComplete:NO];
        popup.dates = [self relativeDatesForLanguage:language];
        NSTableView *table = [self tableOf:popup];
        NSTableColumn *dateColumn = [table tableColumnWithIdentifier:@"date"];
        NSTableColumn *valueColumn = [table tableColumnWithIdentifier:@"value"];
        const CGFloat totalBefore = dateColumn.width + valueColumn.width;

        [popup sizeDateColumnToFit];

        NSCell *cell = [dateColumn.dataCell copy];
        for (NSString *date in popup.dates) {
            cell.objectValue = date;
            XCTAssertGreaterThanOrEqual(dateColumn.width, ceil(cell.cellSize.width), @"%@: %@", language, date);
        }
        XCTAssertEqualWithAccuracy(dateColumn.width + valueColumn.width, totalBefore, 0.5,
                                   @"%@: the table's columns changed total width", language);
        [popup shutdown];
    }
}

- (void)testDatesThatFitLeaveTheColumnsAlone {
    PopupDateColumnWidthTestPopup *popup = [[PopupDateColumnWidthTestPopup alloc] initForAutoComplete:NO];
    NSTableView *table = [self tableOf:popup];
    NSTableColumn *dateColumn = [table tableColumnWithIdentifier:@"date"];
    NSTableColumn *valueColumn = [table tableColumnWithIdentifier:@"value"];
    const CGFloat dateWidth = dateColumn.width;
    const CGFloat valueWidth = valueColumn.width;
    popup.dates = @[ @"Yesterday", @"1 hour ago" ];
    [popup sizeDateColumnToFit];
    XCTAssertEqual(dateColumn.width, dateWidth);
    XCTAssertEqual(valueColumn.width, valueWidth);
    [popup shutdown];
}

@end
