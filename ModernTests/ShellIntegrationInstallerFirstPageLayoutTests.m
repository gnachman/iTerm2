//
//  ShellIntegrationInstallerFirstPageLayoutTests.m
//  ModernTests
//
//  QA finding F-406: on the shell integration installer's first page, the
//  German utilities checkbox read “iTerm2-Dienstprogramm…” and its
//  description was cut after the first line, because both had fixed frames
//  sized for English. These give the real controls each shipped language's
//  text and check that it fits without running into the buttons.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// Stands in for the window controller as the nib's owner.
@interface ShellIntegrationFirstPageNibOwnerForTesting : NSObject
@end

@implementation ShellIntegrationFirstPageNibOwnerForTesting
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
}
- (id)valueForUndefinedKey:(NSString *)key {
    return nil;
}
- (IBAction)cancel:(id)sender {}
- (void)shellIntegrationInstallerContentSizeDidChange {}
@end

@protocol ShellIntegrationFirstPageLayoutForTesting <NSObject>
@property(nonatomic, readonly) NSView *view;
@property(nonatomic, strong) NSButton *utilities;
@property(nonatomic, strong) NSTextField *utilitiesLabel;
@property(nonatomic, strong) NSTextField *descriptionLabel;
@optional
- (void)fitUtilitiesToContent;
@end

@interface ShellIntegrationInstallerFirstPageLayoutTests : XCTestCase
@end

@implementation ShellIntegrationInstallerFirstPageLayoutTests {
    NSArray *_topLevelObjects;
}

- (NSViewController<ShellIntegrationFirstPageLayoutForTesting> *)loadViewController {
    ShellIntegrationFirstPageNibOwnerForTesting *owner = [[ShellIntegrationFirstPageNibOwnerForTesting alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"iTermShellIntegrationWindowController" bundle:[NSBundle mainBundle]];
    NSArray *objects = nil;
    XCTAssertTrue([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    _topLevelObjects = objects;
    Class theClass = NSClassFromString(@"iTermShellIntegrationFirstPageViewController");
    for (id object in objects) {
        if ([object isKindOfClass:theClass]) {
            return object;
        }
    }
    XCTFail(@"No first page view controller in the nib");
    return nil;
}

- (NSString *)stringForKey:(NSString *)key table:(NSString *)table language:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:table
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings[key], @"No %@ for %@", key, language);
    return strings[key] ?: @"";
}

- (void)checkLanguage:(NSString *)language {
    NSViewController<ShellIntegrationFirstPageLayoutForTesting> *vc = [self loadViewController];
    NSView *view = vc.view;
    NSButton *checkbox = vc.utilities;
    NSTextField *label = vc.utilitiesLabel;
    NSMutableArray<NSButton *> *pushButtons = [NSMutableArray array];
    for (NSView *subview in view.subviews) {
        if ([subview isKindOfClass:[NSButton class]] && subview != checkbox) {
            [pushButtons addObject:(NSButton *)subview];
        }
    }
    XCTAssertEqual(pushButtons.count, 2);
    NSMutableDictionary<NSValue *, NSValue *> *buttonFrames = [NSMutableDictionary dictionary];
    for (NSButton *button in pushButtons) {
        buttonFrames[[NSValue valueWithNonretainedObject:button]] = [NSValue valueWithRect:button.frame];
    }

    NSString *checkboxTitle;
    NSString *description;
    NSString *learnMore;
    if ([language isEqualToString:@"en"]) {
        // English is the nib's own text.
        checkboxTitle = checkbox.title;
        description = label.stringValue;
        learnMore = @"";
    } else {
        checkboxTitle = [self stringForKey:@"ntQ-Ku-Hh9.title"
                                     table:@"iTermShellIntegrationWindowController"
                                  language:language];
        description = [self stringForKey:@"cyF-wg-XYY.title"
                                   table:@"iTermShellIntegrationWindowController"
                                language:language];
        learnMore = [self stringForKey:@"ShellIntegrationInstaller.LearnMore"
                                 table:@"Localizable"
                              language:language];
    }
    checkbox.title = checkboxTitle;
    label.attributedStringValue = [[NSAttributedString alloc] initWithString:[description stringByAppendingString:learnMore]
                                                                  attributes:@{ NSFontAttributeName: label.font }];
    // Before the fix there was no such method and the controls kept their nib frames.
    if ([vc respondsToSelector:@selector(fitUtilitiesToContent)]) {
        [vc fitUtilitiesToContent];
    }

    XCTAssertLessThanOrEqual(ceil(checkbox.cell.cellSize.width), NSWidth(checkbox.frame), @"%@ checkbox clipped", language);
    XCTAssertLessThanOrEqual(NSMaxX(checkbox.frame), NSWidth(view.bounds), @"%@", language);
    // Measure the whole text wrapped at the label's width, whether or not the label wraps.
    NSTextFieldCell *wrappingCell = [label.cell copy];
    wrappingCell.wraps = YES;
    wrappingCell.lineBreakMode = NSLineBreakByWordWrapping;
    const CGFloat fittingHeight = ceil([wrappingCell cellSizeForBounds:NSMakeRect(0, 0, NSWidth(label.frame), CGFLOAT_MAX)].height);
    XCTAssertLessThanOrEqual(fittingHeight, NSHeight(label.frame), @"%@ description clipped", language);
    XCTAssertLessThanOrEqual(NSMaxY(label.frame), NSMinY(checkbox.frame) + 1, @"%@ description overlaps checkbox", language);
    for (NSButton *button in pushButtons) {
        const NSRect original = [buttonFrames[[NSValue valueWithNonretainedObject:button]] rectValue];
        XCTAssertTrue(NSEqualRects(original, button.frame), @"%@ button moved", language);
        XCTAssertGreaterThanOrEqual(NSMinY(label.frame), NSMaxY(button.frame), @"%@ description overlaps buttons", language);
    }
    XCTAssertLessThanOrEqual(NSMaxY(checkbox.frame), NSHeight(view.bounds), @"%@", language);
}

- (void)testUtilitiesFitInEveryLanguage {
    for (NSString *language in @[ @"en", @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        [self checkLanguage:language];
    }
}

// T-94: the “Learn more.” links had no font, so they drew in Helvetica 12 instead of the
// label's font.
- (void)testLearnMoreLinksUseTheLabelFont {
    NSViewController<ShellIntegrationFirstPageLayoutForTesting> *vc = [self loadViewController];
    XCTAssertNotNil(vc.view);
    for (NSTextField *label in @[ vc.descriptionLabel, vc.utilitiesLabel ]) {
        NSAttributedString *string = label.attributedStringValue;
        __block BOOL sawLink = NO;
        [string enumerateAttributesInRange:NSMakeRange(0, string.length)
                                   options:0
                                usingBlock:^(NSDictionary<NSAttributedStringKey, id> *attrs, NSRange range, BOOL *stop) {
            if (attrs[NSLinkAttributeName]) {
                sawLink = YES;
            }
            XCTAssertEqualObjects(attrs[NSFontAttributeName], label.font,
                                  @"%@", [string.string substringWithRange:range]);
        }];
        XCTAssertTrue(sawLink, @"%@", string.string);
    }
}

@end
