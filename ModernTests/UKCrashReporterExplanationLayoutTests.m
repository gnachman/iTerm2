//
//  UKCrashReporterExplanationLayoutTests.m
//  ModernTests
//
//  QA finding F-228: the explanation at the top of the crash reporter has a
//  fixed frame sized for English, so the German text was cut off after its
//  fifth line. These load the real nib, give the label every shipped
//  translation of both explanations it can show, and check the crash
//  reporter makes it tall enough and moves the tab view out of its way.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// Stands in for UKCrashReporter as the nib's owner so loading the nib doesn't
// run UKCrashReporter's -awakeFromNib, which shows the window.
@interface UKCrashReporterNibOwnerForTesting : NSObject
@property(nonatomic, strong) NSWindow *reportWindow;
@property(nonatomic, strong) NSTextView *informationField;
@property(nonatomic, strong) NSTextView *crashLogField;
@property(nonatomic, strong) NSTextField *explanationField;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSButton *sendButton;
@property(nonatomic, strong) NSButton *remindButton;
@property(nonatomic, strong) NSButton *discardButton;
@property(nonatomic, strong) NSTabView *switchTabView;
@end

@implementation UKCrashReporterNibOwnerForTesting
- (IBAction)sendCrashReport:(id)sender {}
- (IBAction)remindMeLater:(id)sender {}
- (IBAction)discardCrashReport:(id)sender {}
@end

@protocol UKCrashReporterExplanationLayoutForTesting <NSObject>
- (void)fitExplanationField;
@end

@interface UKCrashReporterExplanationLayoutTests : XCTestCase
@end

@implementation UKCrashReporterExplanationLayoutTests {
    NSArray *_topLevelObjects;
}

+ (NSArray<NSString *> *)translations {
    return @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ];
}

- (NSString *)stringForKey:(NSString *)key table:(NSString *)table localization:(NSString *)localization {
    NSString *path = [[NSBundle mainBundle] pathForResource:table
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:localization];
    NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings[key], @"No %@ in %@ for %@", key, table, localization);
    return strings[key];
}

// Both texts the label can show: the crash explanation (from the nib) and the
// feedback explanation (from Localizable).
- (NSArray<NSString *> *)explanationsForLocalization:(NSString *)localization {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSString *crash = [self stringForKey:@"84.title" table:@"UKCrashReporter" localization:localization];
    NSString *feedback = [self stringForKey:@"CrashReporter.FeedbackExplanation" table:@"Localizable" localization:localization];
    for (NSString *string in @[ crash ?: @"", feedback ?: @"" ]) {
        [result addObject:[string stringByReplacingOccurrencesOfString:@"{APPNAME}" withString:@"iTerm2"]];
    }
    return result;
}

- (UKCrashReporterNibOwnerForTesting *)loadNib {
    UKCrashReporterNibOwnerForTesting *owner = [[UKCrashReporterNibOwnerForTesting alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UKCrashReporter" bundle:[NSBundle mainBundle]];
    XCTAssertNotNil(nib);
    NSArray *objects = nil;
    XCTAssertTrue([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    _topLevelObjects = objects;
    XCTAssertNotNil(owner.explanationField);
    XCTAssertNotNil(owner.switchTabView);
    return owner;
}

// Runs the crash reporter's layout on the nib's views with `string` shown.
- (void)fitString:(NSString *)string owner:(UKCrashReporterNibOwnerForTesting *)owner {
    Class reporterClass = NSClassFromString(@"UKCrashReporter");
    XCTAssertNotNil(reporterClass);
    // Not initialized: -init loads the nib and shows the window.
    id reporter = [reporterClass alloc];
    XCTAssertTrue([reporter respondsToSelector:@selector(fitExplanationField)],
                  @"The crash reporter has no way to fit its explanation");
    [reporter setValue:owner.explanationField forKey:@"explanationField"];
    [reporter setValue:owner.switchTabView forKey:@"switchTabView"];
    owner.explanationField.stringValue = string;
    if ([reporter respondsToSelector:@selector(fitExplanationField)]) {
        [(id<UKCrashReporterExplanationLayoutForTesting>)reporter fitExplanationField];
    }
    [reporter setValue:nil forKey:@"explanationField"];
    [reporter setValue:nil forKey:@"switchTabView"];
}

- (CGFloat)heightNeededByLabel:(NSTextField *)label {
    const NSRect bounds = NSMakeRect(0, 0, NSWidth(label.frame), CGFLOAT_MAX);
    return ceil([label.cell cellSizeForBounds:bounds].height);
}

- (void)testGermanCrashExplanationNeedsMoreThanTheNibHeight {
    // Guards the premise: the string QA saw clipped doesn't fit the frame
    // the nib gives it.
    UKCrashReporterNibOwnerForTesting *owner = [self loadNib];
    NSTextField *label = owner.explanationField;
    label.stringValue = [self explanationsForLocalization:@"de"][0];
    XCTAssertGreaterThan([self heightNeededByLabel:label], NSHeight(label.frame));
}

- (void)testEveryExplanationFits {
    NSMutableArray<NSString *> *languages = [[UKCrashReporterExplanationLayoutTests translations] mutableCopy];
    [languages addObject:@"en"];
    for (NSString *language in languages) {
        NSArray<NSString *> *strings;
        if ([language isEqualToString:@"en"]) {
            UKCrashReporterNibOwnerForTesting *owner = [self loadNib];
            strings = @[ [owner.explanationField.stringValue stringByReplacingOccurrencesOfString:@"{APPNAME}" withString:@"iTerm2"] ];
        } else {
            strings = [self explanationsForLocalization:language];
        }
        for (NSString *string in strings) {
            UKCrashReporterNibOwnerForTesting *owner = [self loadNib];
            NSTextField *label = owner.explanationField;
            const CGFloat top = NSMaxY(label.frame);
            const NSRect originalTabFrame = owner.switchTabView.frame;
            [self fitString:string owner:owner];

            XCTAssertGreaterThanOrEqual(NSHeight(label.frame), [self heightNeededByLabel:label],
                                        @"%@ explanation clipped: %@", language, string);
            XCTAssertEqual(NSMaxY(label.frame), top, @"%@: the label's top moved", language);
            XCTAssertLessThanOrEqual(NSMaxY(owner.switchTabView.frame), NSMinY(label.frame),
                                     @"%@: the tab view overlaps the explanation", language);
            XCTAssertEqual(NSMinY(owner.switchTabView.frame), NSMinY(originalTabFrame),
                           @"%@: the tab view's bottom moved", language);
        }
    }
}

- (void)testEnglishLayoutIsUnchanged {
    UKCrashReporterNibOwnerForTesting *owner = [self loadNib];
    const NSRect labelFrame = owner.explanationField.frame;
    const NSRect tabFrame = owner.switchTabView.frame;
    [self fitString:owner.explanationField.stringValue owner:owner];
    XCTAssertTrue(NSEqualRects(owner.explanationField.frame, labelFrame));
    XCTAssertTrue(NSEqualRects(owner.switchTabView.frame, tabFrame));
}

@end
