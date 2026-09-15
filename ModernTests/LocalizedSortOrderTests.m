//
//  LocalizedSortOrderTests.m
//  ModernTests
//
//  Regression tests for two lists that sorted by a stable English key but
//  displayed localized names, so localized users saw an apparently random
//  order. The fixes sort by the localized DISPLAY name instead. The test host
//  runs in English, so these tests inject localized display names via a block
//  and assert the sort key is the display name, not the underlying English key.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "iTermToolbeltView.h"
#import "iTermAdvancedSettingsViewController.h"
#import "iTermAdvancedSettingsModel.h"

@interface LocalizedSortOrderTests : XCTestCase
@end

@implementation LocalizedSortOrderTests

#pragma mark - Toolbelt tool menu ordering

// The tool names double as stable English keys but the menu displays their
// localized titles. Feed a set whose localized display order is the reverse of
// the raw key order and prove the result is ordered by the display name.
- (void)testToolNamesSortByLocalizedDisplayName {
    NSArray<NSString *> *keys = @[ @"Apple", @"Mango", @"Zebra" ];
    // Localized display names chosen so their order is the reverse of the keys:
    // Apple->"Zulu", Mango->"Mike", Zebra->"Alpha".
    NSDictionary<NSString *, NSString *> *display = @{
        @"Apple": @"Zulu",
        @"Mango": @"Mike",
        @"Zebra": @"Alpha",
    };
    NSArray<NSString *> *sorted =
        [iTermToolbeltView toolNames:keys
             sortedByLocalizedNameUsingBlock:^NSString *(NSString *name) {
        return display[name];
    }];
    // Ordered by display name (Alpha, Mike, Zulu) which is the reverse of key order.
    NSArray<NSString *> *expected = @[ @"Zebra", @"Mango", @"Apple" ];
    XCTAssertEqualObjects(sorted, expected);
}

// Sorting by the raw key would have produced the input order; prove the display
// order actually differs so the previous test is meaningful.
- (void)testToolNamesLocalizedOrderDiffersFromKeyOrder {
    NSArray<NSString *> *keys = @[ @"Apple", @"Mango", @"Zebra" ];
    NSArray<NSString *> *keyOrder = [keys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    XCTAssertEqualObjects(keyOrder, keys);  // keys are already in ascending key order

    NSDictionary<NSString *, NSString *> *display = @{
        @"Apple": @"Zulu",
        @"Mango": @"Mike",
        @"Zebra": @"Alpha",
    };
    NSArray<NSString *> *sorted =
        [iTermToolbeltView toolNames:keys
             sortedByLocalizedNameUsingBlock:^NSString *(NSString *name) {
        return display[name];
    }];
    XCTAssertNotEqualObjects(sorted, keyOrder);
}

// For English (identity display mapping) the order must be unchanged.
- (void)testToolNamesEnglishOrderUnchanged {
    NSArray<NSString *> *keys = @[ @"Zebra", @"Apple", @"Mango" ];
    NSArray<NSString *> *sorted =
        [iTermToolbeltView toolNames:keys
             sortedByLocalizedNameUsingBlock:^NSString *(NSString *name) {
        return name;  // English: display name equals key.
    }];
    XCTAssertEqualObjects(sorted, (@[ @"Apple", @"Mango", @"Zebra" ]));
}

#pragma mark - Advanced settings category grouping

- (NSDictionary *)settingWithCategory:(NSString *)category description:(NSString *)description {
    return @{
        kAdvancedSettingCategory: category,
        kAdvancedSettingDescription: description,
        kAdvancedSettingIdentifier: description,
    };
}

// The category header rows display the localized category name, so the groups
// must be ordered by that localized name. Inject localized category names whose
// order is the reverse of the English category keys and prove the comparator
// orders groups by the localized name.
- (void)testAdvancedSettingGroupsSortByLocalizedCategory {
    // English categories in ascending key order: "Aaa" < "Mmm" < "Zzz".
    NSDictionary *aaa = [self settingWithCategory:@"Aaa" description:@"one"];
    NSDictionary *zzz = [self settingWithCategory:@"Zzz" description:@"two"];
    // Localized names reverse the order: Aaa->"Zulu", Zzz->"Alpha".
    NSDictionary<NSString *, NSString *> *localized = @{ @"Aaa": @"Zulu", @"Zzz": @"Alpha" };
    NSString *(^block)(NSString *) = ^NSString *(NSString *english) {
        return localized[english];
    };

    NSComparisonResult result =
        [iTermAdvancedSettingsViewController compareAdvancedSettingDict:aaa
                                                                toDict:zzz
                                                localizedCategoryBlock:block];
    // "Zulu" > "Alpha", so the "Aaa"-keyed dict sorts AFTER the "Zzz"-keyed dict.
    XCTAssertEqual(result, NSOrderedDescending);

    // Full sort to confirm the resulting group order follows the localized name.
    NSArray<NSDictionary *> *sorted =
        [@[ aaa, zzz ] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *l, NSDictionary *r) {
        return [iTermAdvancedSettingsViewController compareAdvancedSettingDict:l
                                                                       toDict:r
                                                       localizedCategoryBlock:block];
    }];
    XCTAssertEqualObjects(sorted[0][kAdvancedSettingCategory], @"Zzz");  // localized "Alpha"
    XCTAssertEqualObjects(sorted[1][kAdvancedSettingCategory], @"Aaa");  // localized "Zulu"
}

// Within a single category the rows stay alphabetized by description.
- (void)testAdvancedSettingRowsSortByDescriptionWithinCategory {
    NSDictionary *first = [self settingWithCategory:@"Same" description:@"apple"];
    NSDictionary *second = [self settingWithCategory:@"Same" description:@"banana"];
    NSString *(^identity)(NSString *) = ^NSString *(NSString *english) { return english; };

    NSComparisonResult result =
        [iTermAdvancedSettingsViewController compareAdvancedSettingDict:second
                                                                toDict:first
                                                localizedCategoryBlock:identity];
    XCTAssertEqual(result, NSOrderedDescending);  // "banana" after "apple"
}

// With an identity (English) mapping, grouping still follows the English keys,
// proving the change does not disturb the English ordering.
- (void)testAdvancedSettingEnglishGroupingUnchanged {
    NSDictionary *aaa = [self settingWithCategory:@"Aaa" description:@"x"];
    NSDictionary *zzz = [self settingWithCategory:@"Zzz" description:@"y"];
    NSString *(^identity)(NSString *) = ^NSString *(NSString *english) { return english; };

    NSComparisonResult result =
        [iTermAdvancedSettingsViewController compareAdvancedSettingDict:aaa
                                                                toDict:zzz
                                                localizedCategoryBlock:identity];
    XCTAssertEqual(result, NSOrderedAscending);  // "Aaa" before "Zzz"
}

@end
