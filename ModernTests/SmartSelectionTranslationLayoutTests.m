//
//  SmartSelectionTranslationLayoutTests.m
//  ModernTests
//
//  QA findings F-305 (Russian) and F-319 (German): the Smart Selection rules
//  sheet clipped its title, the “No rule selected” placeholder, the Load
//  Defaults button, the debug logging checkbox, the regular expression label
//  and both links. The sheet lives in PreferencePanel.xib, which is too big
//  to instantiate in a test, so these read frames from the xib in the source
//  tree, rebuild the controls the controller lays out, and check that every
//  shipped translation fits.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@protocol SmartSelectionLayoutForTesting <NSObject>
- (void)layoutForTranslations;
@end

@protocol SmartSelectionLinkButtonForTesting <NSObject>
- (void)configureLinkAppearance;
@end

@interface SmartSelectionTranslationLayoutTests : XCTestCase
@end

@implementation SmartSelectionTranslationLayoutTests {
    NSXMLDocument *_xib;
}

+ (NSArray<NSString *> *)languages {
    return @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ];
}

- (void)setUp {
    NSString *source = [NSString stringWithUTF8String:__FILE__];
    NSString *xibPath = [[[source stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"sources/Settings/Base.lproj/PreferencePanel.xib"];
    NSError *error = nil;
    _xib = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:xibPath] options:0 error:&error];
    XCTAssertNotNil(_xib, @"%@", error);
}

- (NSString *)stringForKey:(NSString *)key table:(NSString *)table language:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:table
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary<NSString *, NSString *> *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings[key], @"No %@ in %@ for %@", key, table, language);
    return strings[key] ?: @"";
}

- (NSArray<NSString *> *)translationsOfKey:(NSString *)key table:(NSString *)table {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *language in [SmartSelectionTranslationLayoutTests languages]) {
        [result addObject:[self stringForKey:key table:table language:language]];
    }
    return result;
}

- (NSXMLElement *)elementWithID:(NSString *)identifier {
    NSError *error = nil;
    NSString *xpath = [NSString stringWithFormat:@"//*[@id='%@']", identifier];
    NSXMLElement *element = [[_xib nodesForXPath:xpath error:&error] firstObject];
    XCTAssertNotNil(element, @"No %@ in the xib: %@", identifier, error);
    return element;
}

- (NSRect)frameOf:(NSString *)identifier {
    for (NSXMLElement *child in [self elementWithID:identifier].children) {
        if ([child isKindOfClass:NSXMLElement.class] &&
            [child.name isEqualToString:@"rect"] &&
            [[child attributeForName:@"key"].stringValue isEqualToString:@"frame"]) {
            return NSMakeRect([child attributeForName:@"x"].stringValue.doubleValue,
                              [child attributeForName:@"y"].stringValue.doubleValue,
                              [child attributeForName:@"width"].stringValue.doubleValue,
                              [child attributeForName:@"height"].stringValue.doubleValue);
        }
    }
    XCTFail(@"No frame for %@", identifier);
    return NSZeroRect;
}

- (CGFloat)widthOfLabel:(NSString *)string font:(NSFont *)font {
    NSTextField *label = [NSTextField labelWithString:string];
    label.font = font;
    return ceil(label.cell.cellSize.width);
}

#pragma mark - Fixed frames

- (void)testTitleFits {
    const NSRect frame = [self frameOf:@"5924"];
    for (NSString *string in [self translationsOfKey:@"5925.title" table:@"PreferencePanel"]) {
        XCTAssertLessThanOrEqual([self widthOfLabel:string font:[NSFont boldSystemFontOfSize:NSFont.systemFontSize]],
                                 NSWidth(frame), @"%@", string);
    }
    // It stays above the rules table.
    XCTAssertLessThanOrEqual(NSMaxX(frame), NSMaxX([self frameOf:@"5839"]));
}

- (void)testNoRuleSelectedFits {
    const NSRect frame = [self frameOf:@"ZJJ-tz-ZSD"];
    for (NSString *string in [self translationsOfKey:@"Qbk-nR-LNI.title" table:@"PreferencePanel"]) {
        XCTAssertLessThanOrEqual([self widthOfLabel:string font:[NSFont systemFontOfSize:NSFont.systemFontSize]],
                                 NSWidth(frame), @"%@", string);
    }
    // Within the detail area it stands in for.
    const NSRect detail = [self frameOf:@"G9P-jc-glM"];
    XCTAssertGreaterThanOrEqual(NSMinX(frame), NSMinX(detail));
    XCTAssertLessThanOrEqual(NSMaxX(frame), NSMaxX(detail));
}

#pragma mark - Laid out in code

// The controls -layoutForTranslations moves, built with the xib's frames
// and the given titles.
- (id)controllerWithLoadDefaults:(NSString *)loadDefaults
                        checkbox:(NSString *)checkbox
                      regexLabel:(NSString *)regexLabel {
    return [self controllerWithLoadDefaults:loadDefaults
                                   checkbox:checkbox
                                 regexLabel:regexLabel
                                syntaxTitle:@"Syntax Help"
                            visualizerTitle:@"Open Regular Expression Visualizer"];
}

// Built like the nib's iTermLinkButtons.
- (NSButton *)linkWithTitle:(NSString *)title frame:(NSRect)frame {
    Class linkClass = NSClassFromString(@"iTermLinkButton");
    XCTAssertNotNil(linkClass);
    NSButton *link = [[linkClass alloc] initWithFrame:frame];
    link.bezelStyle = NSBezelStyleRounded;
    link.controlSize = NSControlSizeSmall;
    link.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeSmall]];
    link.title = title;
    [(id<SmartSelectionLinkButtonForTesting>)link configureLinkAppearance];
    return link;
}

- (id)controllerWithLoadDefaults:(NSString *)loadDefaults
                        checkbox:(NSString *)checkbox
                      regexLabel:(NSString *)regexLabel
                     syntaxTitle:(NSString *)syntaxTitle
                 visualizerTitle:(NSString *)visualizerTitle {
    NSButton *button = [NSButton buttonWithTitle:loadDefaults target:nil action:nil];
    button.bezelStyle = NSBezelStyleShadowlessSquare;
    button.frame = [self frameOf:@"5879"];

    NSButton *check = [NSButton checkboxWithTitle:checkbox target:nil action:nil];
    check.frame = [self frameOf:@"5961"];

    NSButton *help = [[NSButton alloc] initWithFrame:[self frameOf:@"5897"]];
    help.bezelStyle = NSBezelStyleHelpButton;
    help.title = @"";

    NSTextField *label = [NSTextField wrappingLabelWithString:regexLabel];
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    label.frame = [self frameOf:@"uKX-eX-rFi"];

    NSButton *syntax = [self linkWithTitle:syntaxTitle frame:[self frameOf:@"GPd-jU-wd3"]];
    NSButton *visualizer = [self linkWithTitle:visualizerTitle frame:[self frameOf:@"D33-2s-Z80"]];

    Class controllerClass = NSClassFromString(@"SmartSelectionController");
    id controller = [[controllerClass alloc] initWithWindow:nil];
    XCTAssertTrue([controller respondsToSelector:@selector(layoutForTranslations)],
                  @"The controller doesn't lay out for translations");
    @try {
        [controller setValue:button forKey:@"_loadDefaultsButton"];
        [controller setValue:check forKey:@"logDebugInfo_"];
        [controller setValue:help forKey:@"_helpButton"];
        [controller setValue:label forKey:@"_regexLabel"];
        [controller setValue:syntax forKey:@"_syntaxHelpButton"];
        [controller setValue:visualizer forKey:@"_visualizationButton"];
    } @catch (NSException *exception) {
        XCTFail(@"Missing outlet: %@", exception);
        return nil;
    }
    if ([controller respondsToSelector:@selector(layoutForTranslations)]) {
        [controller layoutForTranslations];
    }
    return controller;
}

- (void)testBottomRowFits {
    NSArray<NSString *> *buttons = [self translationsOfKey:@"5880.title" table:@"PreferencePanel"];
    NSArray<NSString *> *checkboxes = [self translationsOfKey:@"5962.title" table:@"PreferencePanel"];
    for (NSUInteger i = 0; i < buttons.count; i++) {
        id controller = [self controllerWithLoadDefaults:buttons[i] checkbox:checkboxes[i] regexLabel:@"x"];
        NSButton *button = [controller valueForKey:@"_loadDefaultsButton"];
        NSButton *check = [controller valueForKey:@"logDebugInfo_"];
        NSButton *help = [controller valueForKey:@"_helpButton"];
        XCTAssertGreaterThanOrEqual(NSWidth(button.frame), ceil(button.cell.cellSize.width), @"%@", buttons[i]);
        XCTAssertGreaterThanOrEqual(NSWidth(check.frame), ceil(check.cell.cellSize.width), @"%@", checkboxes[i]);
        XCTAssertGreaterThan(NSMinX(check.frame), NSMaxX(button.frame), @"%@", checkboxes[i]);
        XCTAssertLessThan(NSMaxX(check.frame), NSMinX(help.frame), @"%@", checkboxes[i]);
    }
}

- (void)testRegexLabelFits {
    for (NSString *string in [self translationsOfKey:@"yyK-z1-ogF.title" table:@"PreferencePanel"]) {
        id controller = [self controllerWithLoadDefaults:@"x" checkbox:@"x" regexLabel:string];
        NSTextField *label = [controller valueForKey:@"_regexLabel"];
        NSButton *syntax = [controller valueForKey:@"_syntaxHelpButton"];
        const NSRect bounds = NSMakeRect(0, 0, NSWidth(label.frame), CGFLOAT_MAX);
        XCTAssertGreaterThanOrEqual(NSHeight(label.frame), ceil([label.cell cellSizeForBounds:bounds].height), @"%@", string);
        XCTAssertLessThanOrEqual(NSMaxY(syntax.frame), NSMinY(label.frame), @"%@: the link overlaps the label", string);
        // The label's top stays aligned with the text view's.
        XCTAssertEqual(NSMaxY(label.frame), NSMaxY([self frameOf:@"uKX-eX-rFi"]));
    }
}

- (void)testLinksFit {
    // The visualizer link swaps between three titles.
    NSMutableArray<NSString *> *titles = [[self translationsOfKey:@"suE-7b-47n.title" table:@"PreferencePanel"] mutableCopy];
    [titles addObjectsFromArray:[self translationsOfKey:@"SmartSelection.OpenVisualization" table:@"Localizable"]];
    [titles addObjectsFromArray:[self translationsOfKey:@"SmartSelection.CloseVisualization" table:@"Localizable"]];
    [titles addObjectsFromArray:@[ @"Open Regular Expression Visualization",
                                   @"Close Regular Expression Visualization" ]];
    NSArray<NSString *> *syntaxTitles = [self translationsOfKey:@"JCo-OR-EqT.title" table:@"PreferencePanel"];
    const NSRect detail = [self frameOf:@"G9P-jc-glM"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *syntaxTitle = syntaxTitles[i % syntaxTitles.count];
        id controller = [self controllerWithLoadDefaults:@"x"
                                                checkbox:@"x"
                                              regexLabel:@"x"
                                             syntaxTitle:syntaxTitle
                                         visualizerTitle:titles[i]];
        NSButton *visualizer = [controller valueForKey:@"_visualizationButton"];
        NSButton *syntax = [controller valueForKey:@"_syntaxHelpButton"];
        XCTAssertGreaterThanOrEqual(NSWidth(visualizer.frame), ceil(visualizer.cell.cellSize.width), @"%@", titles[i]);
        XCTAssertEqual(NSMaxX(visualizer.frame), NSMaxX([self frameOf:@"D33-2s-Z80"]), @"%@", titles[i]);
        XCTAssertGreaterThanOrEqual(NSMinX(visualizer.frame), 0, @"%@ runs out of the detail view", titles[i]);
        XCTAssertLessThanOrEqual(NSMaxX(visualizer.frame), NSWidth(detail));

        XCTAssertGreaterThanOrEqual(NSWidth(syntax.frame), ceil(syntax.cell.cellSize.width), @"%@", syntaxTitle);
        XCTAssertEqual(NSMaxX(syntax.frame), NSMaxX([self frameOf:@"GPd-jU-wd3"]), @"%@", syntaxTitle);
        XCTAssertGreaterThanOrEqual(NSMinX(syntax.frame), 0, @"%@ runs out of the detail view", syntaxTitle);
    }
}

- (void)testEnglishLayoutIsUnchanged {
    id controller = [self controllerWithLoadDefaults:@"Load Defaults"
                                            checkbox:@"Log debug info to Console.app"
                                          regexLabel:@"Regular expression"];
    XCTAssertTrue(NSEqualRects([[controller valueForKey:@"_loadDefaultsButton"] frame], [self frameOf:@"5879"]));
    XCTAssertTrue(NSEqualRects([[controller valueForKey:@"logDebugInfo_"] frame], [self frameOf:@"5961"]));
    XCTAssertTrue(NSEqualRects([[controller valueForKey:@"_regexLabel"] frame], [self frameOf:@"uKX-eX-rFi"]));
    XCTAssertTrue(NSEqualRects([[controller valueForKey:@"_syntaxHelpButton"] frame], [self frameOf:@"GPd-jU-wd3"]));
    XCTAssertTrue(NSEqualRects([[controller valueForKey:@"_visualizationButton"] frame], [self frameOf:@"D33-2s-Z80"]));
}

@end
