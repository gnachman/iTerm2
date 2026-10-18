//
//  ShellIntegrationInstallerStepsLayoutTests.m
//  ModernTests
//
//  QA finding F-364: in German, the shell integration installer's step list
//  for nushell was cut off after “Schritt 4. nushell lädt Skripte automatisch
//  aus seinem Autoload-” because the text field had a fixed height sized for
//  the English steps. These give the real text field the steps each shipped
//  language shows and check that it grows to fit them without running into
//  the buttons.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// Stands in for the window controller as the nib's owner. Its outlets aren't
// needed, so it ignores them.
@interface ShellIntegrationNibOwnerForTesting : NSObject
@end

@implementation ShellIntegrationNibOwnerForTesting
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
}
- (id)valueForUndefinedKey:(NSString *)key {
    return nil;
}
- (IBAction)cancel:(id)sender {}
- (void)shellIntegrationInstallerContentSizeDidChange {}
@end

@protocol ShellIntegrationStepsLayoutForTesting <NSObject>
@property(nonatomic, readonly) NSView *view;
- (void)sizeStepListToFit;
@end

@interface ShellIntegrationInstallerStepsLayoutTests : XCTestCase
@end

@implementation ShellIntegrationInstallerStepsLayoutTests {
    NSArray *_topLevelObjects;
}

- (NSViewController<ShellIntegrationStepsLayoutForTesting> *)loadViewController {
    ShellIntegrationNibOwnerForTesting *owner = [[ShellIntegrationNibOwnerForTesting alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"iTermShellIntegrationWindowController" bundle:[NSBundle mainBundle]];
    NSArray *objects = nil;
    XCTAssertTrue([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    _topLevelObjects = objects;
    Class theClass = NSClassFromString(@"iTermShellIntegrationPasteShellCommandsViewController");
    for (id object in objects) {
        if ([object isKindOfClass:theClass]) {
            return object;
        }
    }
    XCTFail(@"No steps view controller in the nib");
    return nil;
}

- (NSString *)stringForKey:(NSString *)key language:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable"
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings[key], @"No %@ for %@", key, language);
    return strings[key] ?: @"";
}

// The steps as the view controller formats them, for nushell: while waiting
// to write the script (where QA saw the clipping), and when done.
// -update bolds “Continue to write” in the first and “Done” in the second;
// see -boldIndexForScenario:.
- (NSArray<NSArray<NSString *> *> *)scenariosForLanguage:(NSString *)language {
    NSString *discovered = [[self stringForKey:@"ShellIntegrationInstaller.Discovered" language:language]
                            stringByReplacingOccurrencesOfString:@"%@" withString:@"nu"];
    NSString *nuStep = [[self stringForKey:@"ShellIntegrationInstaller.NuStepFormat" language:language]
                        stringByReplacingOccurrencesOfString:@"%d" withString:@"4"];
    return @[
        @[ discovered,
           [self stringForKey:@"ShellIntegrationInstaller.ContinueToWrite" language:language],
           [self stringForKey:@"ShellIntegrationInstaller.Step3Install" language:language],
           nuStep ],
        @[ discovered,
           [self stringForKey:@"ShellIntegrationInstaller.Wrote" language:language],
           [self stringForKey:@"ShellIntegrationInstaller.Installed" language:language],
           [self stringForKey:@"ShellIntegrationInstaller.NuDone" language:language],
           @"",
           [self stringForKey:@"ShellIntegrationInstaller.Done" language:language] ],
    ];
}

// Matches the fonts and paragraph style
// -[iTermShellIntegrationPasteShellCommandsViewController update] uses. The
// caller picks the line -update would bold.
- (NSAttributedString *)attributedStringForLines:(NSArray<NSString *> *)lines boldIndex:(NSUInteger)boldIndex {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineSpacing = 4;
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger idx, BOOL *stop) {
        NSFont *font = idx == boldIndex ? [NSFont boldSystemFontOfSize:NSFont.systemFontSize] : [NSFont systemFontOfSize:NSFont.systemFontSize];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                       attributes:@{ NSFontAttributeName: font,
                                                                                     NSParagraphStyleAttributeName: paragraphStyle }]];
    }];
    return result;
}

// The line -update bolds: the prompt to continue while waiting to write the
// script, or “Done” at the end.
- (NSUInteger)boldIndexForScenario:(NSArray<NSString *> *)lines {
    return lines.count == 4 ? 1 : lines.count - 1;
}

- (NSTextField *)textFieldOf:(NSViewController *)vc {
    NSTextField *field = [vc valueForKey:@"textField"];
    XCTAssertNotNil(field);
    return field;
}

// Without the empty line after the last newline, which needn't be visible.
- (CGFloat)heightNeededBy:(NSTextField *)field {
    NSMutableAttributedString *text = [field.attributedStringValue mutableCopy];
    while ([text.string hasSuffix:@"\n"]) {
        [text deleteCharactersInRange:NSMakeRange(text.length - 1, 1)];
    }
    NSCell *cell = [field.cell copy];
    cell.attributedStringValue = text;
    const NSRect bounds = NSMakeRect(0, 0, NSWidth(field.frame), CGFLOAT_MAX);
    return ceil([cell cellSizeForBounds:bounds].height);
}

- (void)testGermanNushellStepsNeedMoreThanTheNibHeight {
    // Guards the premise: the steps QA saw clipped don't fit the field the
    // nib gives them.
    NSViewController *vc = [self loadViewController];
    NSTextField *field = [self textFieldOf:vc];
    field.attributedStringValue = [self attributedStringForLines:[self scenariosForLanguage:@"de"][0] boldIndex:1];
    XCTAssertGreaterThan([self heightNeededBy:field], NSHeight(field.frame));
}

- (void)testStepsFitInEveryLanguage {
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        for (NSArray<NSString *> *lines in [self scenariosForLanguage:language]) {
            NSViewController<ShellIntegrationStepsLayoutForTesting> *vc = [self loadViewController];
            XCTAssertTrue([vc respondsToSelector:@selector(sizeStepListToFit)], @"The steps don't grow to fit");
            NSTextField *field = [self textFieldOf:vc];
            NSButton *continueButton = [vc valueForKey:@"continueButton"];
            const CGFloat topMargin = NSHeight(vc.view.frame) - NSMaxY(field.frame);
            const CGFloat gapAboveButtons = NSMinY(field.frame) - NSMaxY(continueButton.frame);
            // The push buttons along the bottom (Go Back, Cancel, Skip,
            // Continue) and where they start.
            NSMutableArray<NSButton *> *bottomButtons = [NSMutableArray array];
            NSMutableArray<NSNumber *> *bottomButtonYs = [NSMutableArray array];
            for (NSView *subview in vc.view.subviews) {
                if ([subview isKindOfClass:NSButton.class] && NSMaxY(subview.frame) < NSMinY(field.frame)) {
                    [bottomButtons addObject:(NSButton *)subview];
                    [bottomButtonYs addObject:@(NSMinY(subview.frame))];
                }
            }
            XCTAssertEqual(bottomButtons.count, 4u);

            field.attributedStringValue = [self attributedStringForLines:lines boldIndex:[self boldIndexForScenario:lines]];
            if ([vc respondsToSelector:@selector(sizeStepListToFit)]) {
                [vc sizeStepListToFit];
            }

            XCTAssertGreaterThanOrEqual(NSHeight(field.frame), [self heightNeededBy:field],
                                        @"%@ steps clipped: %@", language, lines);
            XCTAssertEqualWithAccuracy(NSHeight(vc.view.frame) - NSMaxY(field.frame), topMargin, 0.5,
                                       @"%@: the field's top moved", language);
            XCTAssertEqualWithAccuracy(NSMinY(field.frame) - NSMaxY(continueButton.frame), gapAboveButtons, 0.5,
                                       @"%@: the field ran into the buttons", language);
            for (NSUInteger i = 0; i < bottomButtons.count; i++) {
                XCTAssertEqual(NSMinY(bottomButtons[i].frame), bottomButtonYs[i].doubleValue,
                               @"%@: %@ moved", language, bottomButtons[i].title);
                XCTAssertLessThanOrEqual(NSMaxY(bottomButtons[i].frame), NSMinY(field.frame),
                                         @"%@: %@ overlaps the steps", language, bottomButtons[i].title);
            }
        }
    }
}

@end
