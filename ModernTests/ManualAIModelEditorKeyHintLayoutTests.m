//
//  ManualAIModelEditorKeyHintLayoutTests.m
//  ModernTests
//
//  QA finding F-140: the hint under “API key” in the manual AI model editor
//  had a fixed two-line height, so the German hint for a gateway endpoint was
//  cut off after its second line. These pin that the editor reserves enough
//  room for every hint it can show in each shipped language, and that the
//  controls below the hint move down instead of overlapping it. They also pin
//  that every hint fits the two lines the Settings > General > AI hint has.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

// The editor is private to GeneralPreferencesViewController.m. Look it up by
// name and talk to it through this protocol.
@protocol ManualAIModelEditorKeyHintForTesting <NSObject>
- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                            isEditing:(BOOL)isEditing;
- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                            isEditing:(BOOL)isEditing
                    apiKeyHintStrings:(NSArray<NSString *> *)apiKeyHintStrings;
@property(nonatomic, readonly) NSWindow *window;
@end

@interface ManualAIModelEditorKeyHintLayoutTests : XCTestCase
@end

@implementation ManualAIModelEditorKeyHintLayoutTests

// Every shipped translation. English has no compiled table; its hints come
// from the editor's own strings (see testEnglishHintsFitTheEditor).
+ (NSArray<NSString *> *)translations {
    return @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ];
}

// The English hints that take more than one line.
- (NSArray<NSString *> *)longEnglishHints {
    return @[
        @"No API key is sent automatically, since this endpoint is not run by the model’s provider. Choose the key it needs, or use a custom header.",
        @"No API key is sent to a local endpoint. If it requires authentication, use a custom header.",
        @"No API key is sent. If the endpoint requires authentication, use a custom header.",
    ];
}

// A manual model at a third-party gateway with the Automatic key choice, which
// shows the longest hint (AIKeyHint.UnrecognizedHost).
- (NSDictionary *)gatewayConfiguration {
    return @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": @"some-model",
        @"url": @"https://openrouter.ai/api/v1/chat/completions",
        @"api": @1,
        @"contextWindowTokens": @8192,
        @"maxResponseTokens": @1024,
        @"credential": @"automatic",
    };
}

// The translated text of every AIKeyHint.* string, with each provider name
// substituted into the ones that take one.
- (NSArray<NSString *> *)hintStringsForLocalization:(NSString *)localization {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable"
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:localization];
    NSDictionary<NSString *, NSString *> *table = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(table, @"No Localizable.strings for %@", localization);
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (NSString *key in table) {
        if (![key hasPrefix:@"AIKeyHint."]) {
            continue;
        }
        if ([table[key] containsString:@"%@"]) {
            for (NSString *provider in @[ @"OpenAI", @"Anthropic", @"Gemini", @"DeepSeek" ]) {
                [result addObject:[table[key] stringByReplacingOccurrencesOfString:@"%@" withString:provider]];
            }
        } else {
            [result addObject:table[key]];
        }
    }
    XCTAssertGreaterThanOrEqual(result.count, 8u, @"Missing hints for %@", localization);
    return result;
}

- (id<ManualAIModelEditorKeyHintForTesting>)editorWithHintStrings:(NSArray<NSString *> *)strings {
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    XCTAssertNotNil(editorClass);
    id editor = [editorClass alloc];
    XCTAssertTrue([editor respondsToSelector:@selector(initWithConfiguration:isEditing:apiKeyHintStrings:)],
                  @"The editor has no way to size its key hint for given strings");
    if (![editor respondsToSelector:@selector(initWithConfiguration:isEditing:apiKeyHintStrings:)]) {
        return nil;
    }
    return [editor initWithConfiguration:[self gatewayConfiguration]
                               isEditing:YES
                       apiKeyHintStrings:strings];
}

- (NSTextField *)hintLabelOfEditor:(id)editor {
    id label = [(NSObject *)editor valueForKey:@"apiKeyHintLabel"];
    XCTAssertTrue([label isKindOfClass:NSTextField.class]);
    return label;
}

// The height `label` needs to show `string` in full at its own width.
- (CGFloat)heightNeededByLabel:(NSTextField *)label toShow:(NSString *)string {
    label.stringValue = string;
    const NSRect bounds = NSMakeRect(0, 0, NSWidth(label.frame), CGFLOAT_MAX);
    return ceil([label.cell cellSizeForBounds:bounds].height);
}

// The label fits each string and nothing in the form overlaps it or runs into
// the button row.
- (void)assertEditor:(id<ManualAIModelEditorKeyHintForTesting>)editor
            fitsHints:(NSArray<NSString *> *)strings
             language:(NSString *)language {
    NSTextField *label = [self hintLabelOfEditor:editor];
    XCTAssertEqual(label.maximumNumberOfLines, 0, @"The hint must not be capped at a line count");
    for (NSString *string in strings) {
        XCTAssertGreaterThanOrEqual(NSHeight(label.frame), [self heightNeededByLabel:label toShow:string],
                                    @"%@ hint clipped: %@", language, string);
    }

    NSTextField *contextField = [(NSObject *)editor valueForKey:@"contextField"];
    XCTAssertLessThanOrEqual(NSMaxY(contextField.frame), NSMinY(label.frame),
                             @"%@: the row below the hint overlaps it", language);
    NSPopUpButton *credentialPopup = [(NSObject *)editor valueForKey:@"credentialPopup"];
    XCTAssertLessThanOrEqual(NSMaxY(label.frame), NSMinY(credentialPopup.frame),
                             @"%@: the hint overlaps the API key row", language);

    // The last control in the form (the custom headers +/- control) stays
    // above the Save/Cancel/Test row, whose top is at 46.
    NSView *content = editor.window.contentView;
    NSSegmentedControl *addRemove = nil;
    for (NSView *view in content.subviews) {
        if ([view isKindOfClass:NSSegmentedControl.class]) {
            addRemove = (NSSegmentedControl *)view;
        }
    }
    XCTAssertNotNil(addRemove);
    XCTAssertGreaterThanOrEqual(NSMinY(addRemove.frame), 46, @"%@: the form runs into the buttons", language);
    for (NSView *view in content.subviews) {
        XCTAssertLessThanOrEqual(NSMaxY(view.frame), NSHeight(content.frame),
                                 @"%@: %@ is above the top of the window", language, view);
    }
}

- (void)testGermanGatewayHintNeedsMoreThanTwoLines {
    // The string QA saw clipped. Guards the premise of the tests below.
    NSString *german = nil;
    for (NSString *string in [self hintStringsForLocalization:@"de"]) {
        if ([string containsString:@"nicht vom Anbieter des Modells betrieben"]) {
            german = string;
        }
    }
    XCTAssertNotNil(german);
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    id editor = [[(id)editorClass alloc] initWithConfiguration:[self gatewayConfiguration] isEditing:YES];
    NSTextField *label = [self hintLabelOfEditor:editor];
    NSTextField *twoLines = [NSTextField wrappingLabelWithString:@"A\nB"];
    twoLines.font = label.font;
    XCTAssertGreaterThan([self heightNeededByLabel:label toShow:german],
                         [self heightNeededByLabel:twoLines toShow:@"A\nB"]);
}

- (void)testEveryTranslatedHintFitsTheEditor {
    for (NSString *language in [ManualAIModelEditorKeyHintLayoutTests translations]) {
        NSArray<NSString *> *strings = [self hintStringsForLocalization:language];
        id<ManualAIModelEditorKeyHintForTesting> editor = [self editorWithHintStrings:strings];
        [self assertEditor:editor fitsHints:strings language:language];
    }
}

- (void)testEnglishHintsFitTheEditor {
    // With no strings given, the editor sizes the hint for the ones it can
    // show in the running language, which is English here.
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    id<ManualAIModelEditorKeyHintForTesting> editor =
        [[(id)editorClass alloc] initWithConfiguration:[self gatewayConfiguration] isEditing:YES];
    NSTextField *label = [self hintLabelOfEditor:editor];
    NSString *shown = label.stringValue;
    XCTAssertTrue([shown containsString:@"not run by the model’s provider"],
                  @"Precondition: the gateway hint is shown, got %@", shown);
    [self assertEditor:editor fitsHints:[@[ shown ] arrayByAddingObjectsFromArray:[self longEnglishHints]] language:@"en"];
}

- (void)testEnglishKeepsTheDesignedTwoLineHint {
    // Two-line hints leave the form where it was before F-140.
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    id<ManualAIModelEditorKeyHintForTesting> editor =
        [[(id)editorClass alloc] initWithConfiguration:[self gatewayConfiguration] isEditing:YES];
    XCTAssertEqual(NSHeight([self hintLabelOfEditor:editor].frame), 30);
    XCTAssertEqual(NSHeight(editor.window.contentView.frame), 800);
}

- (void)testEveryHintFitsTwoLinesInSettings {
    // Settings > General > AI shows the same hints in a fixed-frame label in
    // PreferencePanel.xib (csg-IK-alh): two lines of the system font in the
    // 685 points that are visible in the tab. Keep this in sync with the xib.
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    label.frame = NSMakeRect(0, 0, 685, 34);
    const CGFloat twoLines = [self heightNeededByLabel:label toShow:@"A\nB"];
    for (NSString *string in [self longEnglishHints]) {
        XCTAssertLessThanOrEqual([self heightNeededByLabel:label toShow:string], twoLines,
                                 @"en Settings hint needs more than two lines: %@", string);
    }
    for (NSString *language in [ManualAIModelEditorKeyHintLayoutTests translations]) {
        for (NSString *string in [self hintStringsForLocalization:language]) {
            XCTAssertLessThanOrEqual([self heightNeededByLabel:label toShow:string], twoLines,
                                     @"%@ Settings hint needs more than two lines: %@", language, string);
        }
    }
}

// The real Settings label, read from PreferencePanel.xib in the source tree
// (instantiating the whole Settings nib in a test has too many side effects).
- (NSRect)rectOfXMLElement:(NSXMLElement *)element {
    NSXMLElement *rect = nil;
    for (NSXMLElement *child in element.children) {
        if ([child isKindOfClass:NSXMLElement.class] &&
            [child.name isEqualToString:@"rect"] &&
            [[child attributeForName:@"key"].stringValue isEqualToString:@"frame"]) {
            rect = child;
        }
    }
    if (!rect) {
        return NSZeroRect;
    }
    return NSMakeRect([rect attributeForName:@"x"].stringValue.doubleValue,
                      [rect attributeForName:@"y"].stringValue.doubleValue,
                      [rect attributeForName:@"width"].stringValue.doubleValue,
                      [rect attributeForName:@"height"].stringValue.doubleValue);
}

- (void)testSettingsHintLabelHasRoomForTwoLines {
    NSString *source = [NSString stringWithUTF8String:__FILE__];
    NSString *xibPath = [[[source stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent:@"sources/Settings/Base.lproj/PreferencePanel.xib"];
    NSError *error = nil;
    NSXMLDocument *xib = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:xibPath]
                                                              options:0
                                                                error:&error];
    XCTAssertNotNil(xib, @"%@", error);
    // csg-IK-alh is the _mainAIAPIKeyHint outlet.
    NSXMLElement *hint = [[xib nodesForXPath:@"//textField[@id='csg-IK-alh']" error:&error] firstObject];
    XCTAssertNotNil(hint, @"%@", error);
    const NSRect frame = [self rectOfXMLElement:hint];
    NSXMLElement *cell = [[hint nodesForXPath:@"textFieldCell" error:nil] firstObject];
    XCTAssertEqualObjects([cell attributeForName:@"lineBreakMode"].stringValue, @"wordWrapping");

    NSTextField *twoLineLabel = [NSTextField wrappingLabelWithString:@""];
    twoLineLabel.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
    twoLineLabel.frame = frame;
    XCTAssertGreaterThanOrEqual(NSHeight(frame), [self heightNeededByLabel:twoLineLabel toShow:@"A\nB"]);
    XCTAssertEqual(NSWidth(frame), 685, @"Keep testEveryHintFitsTwoLinesInSettings in sync");

    // It stays inside its tab and clear of the controls around it.
    NSXMLElement *subviews = (NSXMLElement *)hint.parent;
    NSXMLElement *tabView = (NSXMLElement *)subviews.parent;
    XCTAssertLessThanOrEqual(NSMaxX(frame), NSWidth([self rectOfXMLElement:tabView]));
    for (NSXMLNode *node in subviews.children) {
        if (node == hint || ![node isKindOfClass:NSXMLElement.class]) {
            continue;
        }
        const NSRect siblingFrame = [self rectOfXMLElement:(NSXMLElement *)node];
        XCTAssertFalse(NSIntersectsRect(siblingFrame, frame),
                       @"%@ overlaps the hint", [(NSXMLElement *)node attributeForName:@"id"].stringValue);
    }
}

@end
