//
//  ShellIntegrationInstallerButtonLayoutTests.m
//  ModernTests
//
//  QA finding F-406: in German, the shell integration installer's second page
//  showed “Installationsprogramm herunt…” and the Internet-Free page showed
//  “Überspring…”, because the buttons had fixed widths sized for English.
//  These give the real buttons each shipped language's titles and check that
//  they fit without overlapping their neighbors.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@interface ShellIntegrationButtonNibOwnerForTesting : NSObject
@end

@implementation ShellIntegrationButtonNibOwnerForTesting
- (void)setValue:(id)value forUndefinedKey:(NSString *)key {
}
- (id)valueForUndefinedKey:(NSString *)key {
    return nil;
}
- (IBAction)cancel:(id)sender {}
- (void)shellIntegrationInstallerContentSizeDidChange {}
@end

static NSString *ControlText(NSView *view) {
    if ([view isKindOfClass:[NSButton class]]) {
        return [(NSButton *)view title];
    }
    return [(NSControl *)view stringValue];
}

@interface ShellIntegrationInstallerButtonLayoutTests : XCTestCase
@end

@implementation ShellIntegrationInstallerButtonLayoutTests {
    NSArray *_topLevelObjects;
}

- (NSViewController *)loadViewControllerOfClass:(NSString *)className {
    ShellIntegrationButtonNibOwnerForTesting *owner = [[ShellIntegrationButtonNibOwnerForTesting alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"iTermShellIntegrationWindowController" bundle:[NSBundle mainBundle]];
    NSArray *objects = nil;
    XCTAssertTrue([nib instantiateWithOwner:owner topLevelObjects:&objects]);
    _topLevelObjects = objects;
    Class theClass = NSClassFromString(className);
    for (id object in objects) {
        if ([object isKindOfClass:theClass]) {
            return object;
        }
    }
    XCTFail(@"No %@ in the nib", className);
    return nil;
}

- (NSDictionary<NSString *, NSString *> *)stringsForLanguage:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"iTermShellIntegrationWindowController"
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings, @"%@", language);
    return strings ?: @{};
}

// Loads the view controller, applies the language's XIB strings to its controls (as the
// localized nib would), and calls the fit method the view controller runs in viewDidLoad.
- (NSView *)viewForClass:(NSString *)className
                     fit:(SEL)fit
                    keys:(NSDictionary<NSString *, NSString *> *)keys
                language:(NSString *)language {
    NSViewController *vc = [self loadViewControllerOfClass:className];
    NSView *view = vc.view;
    NSDictionary<NSString *, NSString *> *strings = [self stringsForLanguage:language];
    for (NSView *subview in view.subviews) {
        if (![subview isKindOfClass:[NSControl class]]) {
            continue;
        }
        NSCell *cell = [(NSControl *)subview cell];
        NSString *key = keys[cell.title];
        NSString *translation = key ? strings[[NSString stringWithFormat:@"%@.title", key]] : nil;
        XCTAssertTrue(key == nil || translation != nil, @"%@: no translation of %@", language, cell.title);
        if (translation) {
            cell.title = translation;
        }
    }
    // Fire the hook the app relies on (all outlets and actions are connected by then), not the fit
    // method itself, so this fails if the fit is never triggered.
    XCTAssertTrue([vc respondsToSelector:fit], @"%@ has no %@", className, NSStringFromSelector(fit));
    [vc awakeFromNib];
    return view;
}

- (void)assertControlsFitAndDontOverlap:(NSView *)view language:(NSString *)language {
    NSArray<NSView *> *subviews = [view.subviews filteredArrayUsingPredicate:
                                   [NSPredicate predicateWithBlock:^BOOL(NSView *subview, NSDictionary *bindings) {
        return !subview.isHidden && ([subview isKindOfClass:[NSButton class]] ||
                                     ([subview isKindOfClass:[NSTextField class]] && NSHeight(subview.frame) < 20));
    }]];
    for (NSView *subview in subviews) {
        NSControl *control = (NSControl *)subview;
        if ([subview isKindOfClass:[NSButton class]] && [(NSButton *)subview bezelStyle] == NSBezelStyleRounded &&
            [(NSButton *)subview controlSize] == NSControlSizeRegular) {
            XCTAssertLessThanOrEqual(ceil(control.cell.cellSize.width), NSWidth(subview.frame),
                                     @"%@: “%@” clipped", language, ControlText(control));
        }
        XCTAssertGreaterThanOrEqual(NSMinX(subview.frame), 0, @"%@: “%@”", language, control.stringValue);
        XCTAssertLessThanOrEqual(NSMaxX(subview.frame), NSWidth(view.bounds), @"%@: “%@”", language, control.stringValue);
    }
    for (NSUInteger i = 0; i < subviews.count; i++) {
        for (NSUInteger j = i + 1; j < subviews.count; j++) {
            if (NSMinX(subviews[i].frame) == NSMinX(subviews[j].frame)) {
                // A column of buttons from the nib whose bezels already touch.
                continue;
            }
            // Compare alignment rects: a push button's frame includes its bezel's shadow inset.
            XCTAssertFalse(NSIntersectsRect([subviews[i] alignmentRectForFrame:subviews[i].frame],
                                            [subviews[j] alignmentRectForFrame:subviews[j].frame]),
                           @"%@: “%@” overlaps “%@”", language,
                           ControlText(subviews[i]), ControlText(subviews[j]));
        }
    }
}

- (NSArray<NSString *> *)languages {
    return @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ];
}

- (void)testSecondPageChoiceButtonsFit {
    for (NSString *language in self.languages) {
        NSView *view = [self viewForClass:@"iTermShellIntegrationSecondPageViewController"
                                      fit:NSSelectorFromString(@"fitChoiceButtonsToTitles")
                                     keys:@{ @"Download and Run Installer": @"ncg-Is-RuU",
                                             @"Internet-Free Install": @"naS-Ve-VEB",
                                             @"Downloads the latest version. Runs curl | bash": @"3ik-Ec-g95",
                                             @"Guided manual installation. No download required.": @"oFz-OK-xmV",
                                             @"Cancel": @"Ghw-SZ-fwQ",
                                             @"Go Back": @"dEn-49-J38" }
                                 language:language];
        [self assertControlsFitAndDontOverlap:view language:language];
        // The descriptions beside the buttons must still show their whole text.
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:[NSTextField class]] && NSHeight(subview.frame) < 20) {
                NSTextField *field = (NSTextField *)subview;
                XCTAssertLessThanOrEqual(ceil(field.cell.cellSize.width), NSWidth(field.frame),
                                         @"%@: “%@” clipped", language, field.stringValue);
            }
        }
    }
}

- (void)testInternetFreePageBottomButtonsFit {
    for (NSString *language in self.languages) {
        NSView *view = [self viewForClass:@"iTermShellIntegrationPasteShellCommandsViewController"
                                      fit:NSSelectorFromString(@"fitBottomButtonsToTitles")
                                     keys:@{ @"Cancel": @"BbS-EU-hMu",
                                             @"Skip": @"GW7-My-Ydm",
                                             @"Continue": @"E0t-ip-Qv2",
                                             @"Go Back": @"cmu-UF-19Z" }
                                 language:language];
        [self assertControlsFitAndDontOverlap:view language:language];
    }
}

@end
