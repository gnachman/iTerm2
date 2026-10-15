//
//  BadgeAndIconLabelTranslationTests.m
//  ModernTests
//
//  QA finding F-394: Russian translated both “Badge:” and “Icon:” as
//  “Значок:”, so Settings > Profiles > General had two rows with the same
//  label. This checks that no shipped language gives them the same name.
//

#import <XCTest/XCTest.h>

@interface BadgeAndIconLabelTranslationTests : XCTestCase
@end

@implementation BadgeAndIconLabelTranslationTests

- (void)testBadgeAndIconLabelsDiffer {
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"PreferencePanel"
                                                         ofType:@"strings"
                                                    inDirectory:nil
                                                forLocalization:language];
        NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
        XCTAssertNotNil(strings, @"%@", language);
        // Bp6-8q-9J8 is “Icon:”; the others are the “Badge:” labels.
        NSString *icon = strings[@"Bp6-8q-9J8.title"];
        XCTAssertNotNil(icon, @"%@", language);
        for (NSString *badgeKey in @[ @"7Oa-B2-O5u.title", @"iUy-lI-rM5.title", @"Wf2-tR-45o.title" ]) {
            NSString *badge = strings[badgeKey];
            XCTAssertNotNil(badge, @"%@ %@", language, badgeKey);
            XCTAssertNotEqualObjects(badge, icon, @"%@: Badge and Icon are both “%@”", language, icon);
        }
    }
}

@end
