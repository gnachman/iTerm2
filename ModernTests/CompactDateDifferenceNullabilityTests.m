//
//  CompactDateDifferenceNullabilityTests.m
//  ModernTests
//
//  VALIDATION test for FINDING 2: the non-English branch of
//  +compactDateDifferenceStringFromTimeDelta: returns the result of
//  -[NSDateComponentsFormatter stringFromTimeInterval:] directly. That API is
//  declared `nullable`, but the method lives under NS_ASSUME_NONNULL_BEGIN in
//  NSDateFormatterExtras.h and is typed `+ (NSString *)` (i.e. _Nonnull), so the
//  branch can return nil through a nonnull contract.
//
//  Production site:
//    sources/Categories/NSDateFormatterExtras.m ~156
//      + (NSString *)compactDateDifferenceStringFromTimeDelta:(NSTimeInterval)theTime {
//          NSString *language = [self it_relativeTimeNonEnglishLanguage];
//          if (language) {
//              NSDateComponentsFormatter *formatter = ...abbreviated, 1 unit...;
//              return [formatter stringFromTimeInterval:theTime];   // nullable!
//          }
//          ...English branch returns only non-nil literals...
//      }
//
//  Consumers assume nonnull:
//    - sources/AppKit/iTermApplicationDelegate.m ~555 interpolates the result
//      into a menu title; a nil would render the literal text "(null)".
//    - sources/ClaudeCode/Orchestration/WorkgroupIntrospection.swift ~284
//      does "\(DateFormatter.compactDateDifferenceString(fromTimeDelta: age)) ago"
//      where the import surfaces the ObjC nonnull as a Swift non-optional String;
//      an actual nil there is undefined behavior.
//
//  TESTABILITY: the non-English branch is selected by
//  +it_relativeTimeNonEnglishLanguage, which reads
//  [NSBundle mainBundle].preferredLocalizations. That is the process UI language
//  and is NOT injectable. There is no language-injection overload for this
//  method (unlike +durationString:nonEnglishLanguage:locale:, which was added
//  precisely to make its non-English path testable). So the production
//  non-English path cannot be exercised from the English test host, and no
//  failing test can be written against it. A fix should add an analogous
//  seam (e.g. compactDateDifferenceStringFromTimeDelta:nonEnglishLanguage:) and
//  coalesce the nullable formatter result to a non-nil fallback.
//
//  What this file CAN do:
//    1. Pin the English branch (reached in the English test host) as non-nil and
//       never "(null)" across a range of deltas, including a negative one.
//    2. Characterize the nullability surface of the EXACT formatter the
//       non-English branch builds, to validate/correct the finding's premise.
//       Empirically this formatter does NOT return nil for ordinary finite
//       inputs (out-of-range finite values yield a garbage "0s" placeholder),
//       but it THROWS for non-finite inputs (NaN/infinity). So the realistic
//       failure mode on that path is a CRASH on a non-finite delta rather than a
//       "(null)" string; the nonnull contract is nonetheless unsound because the
//       API it forwards is nullable.
//

#import <XCTest/XCTest.h>
#import "NSDateFormatterExtras.h"

@interface CompactDateDifferenceNullabilityTests : XCTestCase
@end

@implementation CompactDateDifferenceNullabilityTests

// Rebuilds the exact formatter used by the non-English branch so its
// nullability/throw behavior can be characterized without a production seam.
static NSDateComponentsFormatter *NonEnglishBranchFormatter(void) {
    NSDateComponentsFormatter *formatter = [[NSDateComponentsFormatter alloc] init];
    formatter.unitsStyle = NSDateComponentsFormatterUnitsStyleAbbreviated;
    formatter.allowedUnits = (NSCalendarUnitSecond | NSCalendarUnitMinute | NSCalendarUnitHour |
                              NSCalendarUnitDay | NSCalendarUnitWeekOfMonth);
    formatter.maximumUnitCount = 1;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.locale = [NSLocale localeWithLocaleIdentifier:@"fr"];
    formatter.calendar = calendar;
    return formatter;
}

// The English branch (the one reachable in this English-hosted test) honors the
// nonnull contract for every delta, including a negative (future) delta.
- (void)testEnglishBranchNeverReturnsNilOrNullString {
    NSArray<NSNumber *> *deltas = @[ @(-3600), @(-1), @(0), @(0.5), @(30), @(90), @(3700), @(90000), @(700000) ];
    for (NSNumber *d in deltas) {
        NSString *s = [NSDateFormatter compactDateDifferenceStringFromTimeDelta:d.doubleValue];
        XCTAssertNotNil(s, @"delta %@ produced nil", d);
        XCTAssertFalse([s isEqualToString:@"(null)"], @"delta %@ produced literal (null)", d);
        XCTAssertGreaterThan(s.length, 0u, @"delta %@ produced empty string", d);
    }
}

// Characterization: the non-English formatter returns a NON-nil placeholder for
// ordinary and out-of-range finite inputs. This corrects the finding's premise
// that a "(null)" is the likely runtime outcome: for finite deltas it is not.
- (void)testNonEnglishFormatterReturnsNonNilForFiniteInputs {
    NSArray<NSNumber *> *deltas = @[ @(-5), @(0), @(30), @(3600), @(1e18) ];
    for (NSNumber *d in deltas) {
        NSString *s = [NonEnglishBranchFormatter() stringFromTimeInterval:d.doubleValue];
        XCTAssertNotNil(s, @"finite delta %@ unexpectedly produced nil", d);
    }
}

// Characterization: the same formatter THROWS for a non-finite delta. On the
// non-English path this would crash rather than yield "(null)", which is the
// concrete risk the nonnull contract hides. (A NaN/infinite delta is unlikely
// from a date subtraction but is not excluded by the method's type.)
- (void)testNonEnglishFormatterThrowsForNonFiniteInput {
    XCTAssertThrows([NonEnglishBranchFormatter() stringFromTimeInterval:NAN],
                    @"expected NSDateComponentsFormatter to reject NaN");
    XCTAssertThrows([NonEnglishBranchFormatter() stringFromTimeInterval:INFINITY],
                    @"expected NSDateComponentsFormatter to reject +infinity");
}

@end
