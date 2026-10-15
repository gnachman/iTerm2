//
//  ManualAIModelEditorTranslationLayoutTests.m
//  ModernTests
//
//  QA finding F-276: the manual AI model editor's 150-point label column, its
//  checkboxes and its Test Connection button clipped translations with no
//  ellipsis (de “Benutzerdefinierte Head”, pt-BR “Máximo de tokens de res”,
//  ru “Пользовательские заго” and “Проверить соедине…”). These give the real
//  editor every shipped translation of those titles and check that the form
//  makes room for them without controls overlapping.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@protocol ManualAIModelEditorTranslationLayoutForTesting <NSObject>
- (instancetype)initWithConfiguration:(NSDictionary *)configuration isEditing:(BOOL)isEditing;
- (void)layoutForTranslations;
@property(nonatomic, readonly) NSWindow *window;
@end

@interface ManualAIModelEditorTranslationLayoutTests : XCTestCase
@end

@implementation ManualAIModelEditorTranslationLayoutTests

// English title -> catalog key, for every label, checkbox and the Test button.
+ (NSDictionary<NSString *, NSString *> *)keysByEnglishTitle {
    return @{
        @"Preset:": @"AIModelEditor.PresetLabel",
        @"Model:": @"AIModelEditor.ModelLabel",
        @"URL:": @"AIModelEditor.URLLabel",
        @"API:": @"AIModelEditor.APILabel",
        @"API key:": @"AIModelEditor.APIKeyLabel",
        @"Context tokens:": @"AIModelEditor.ContextTokensLabel",
        @"Max response tokens:": @"AIModelEditor.MaxResponseTokensLabel",
        @"Vector store:": @"AIModelEditor.VectorStoreLabel",
        @"Custom headers:": @"AIModelEditor.CustomHeadersLabel",
        @"Discover installed models automatically (Ollama)": @"AIModelEditor.DiscoverModelsAutomatically",
        @"Function calling": @"AIModelEditor.FeatureFunctionCalling",
        @"Streaming responses": @"AIModelEditor.FeatureStreamingResponses",
        @"Vision (image input)": @"AIModelEditor.FeatureVision",
        @"Hosted web search": @"AIModelEditor.FeatureHostedWebSearch",
        @"Hosted file search": @"AIModelEditor.FeatureHostedFileSearch",
        @"Hosted code interpreter": @"AIModelEditor.FeatureHostedCodeInterpreter",
        @"Configurable thinking": @"AIModelEditor.ConfigurableThinking",
        @"Supports temperature": @"AIModelEditor.SupportsTemperature",
        @"Test Connection": @"AIModelEditor.TestConnection",
    };
}

- (NSDictionary<NSString *, NSString *> *)stringsForLanguage:(NSString *)language {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable"
                                                     ofType:@"strings"
                                                inDirectory:nil
                                            forLocalization:language];
    NSDictionary *strings = path ? [NSDictionary dictionaryWithContentsOfFile:path] : nil;
    XCTAssertNotNil(strings, @"%@", language);
    return strings;
}

- (id<ManualAIModelEditorTranslationLayoutForTesting>)newEditor {
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    XCTAssertNotNil(editorClass);
    NSDictionary *configuration = @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": @"some-model",
        @"url": @"http://127.0.0.1:11434/v1/chat/completions",
        @"api": @1,
        @"contextWindowTokens": @8192,
        @"maxResponseTokens": @1024,
    };
    return [[editorClass alloc] initWithConfiguration:configuration isEditing:YES];
}

// The labels, checkboxes and buttons whose titles the test knows, keyed by
// the view.
- (NSMapTable<NSControl *, NSString *> *)titledControlsOf:(NSView *)content {
    NSMapTable *result = [NSMapTable strongToStrongObjectsMapTable];
    NSDictionary *keys = [ManualAIModelEditorTranslationLayoutTests keysByEnglishTitle];
    for (NSView *view in content.subviews) {
        NSString *title = nil;
        if ([view isKindOfClass:NSTextField.class]) {
            title = [(NSTextField *)view stringValue];
        } else if ([view isKindOfClass:NSButton.class]) {
            title = [(NSButton *)view title];
        }
        if (title && keys[title]) {
            [result setObject:keys[title] forKey:view];
        }
    }
    XCTAssertEqual(result.count, keys.count, @"Didn't find every titled control");
    return result;
}

- (void)setTitle:(NSString *)title of:(NSControl *)control {
    if ([control isKindOfClass:NSButton.class]) {
        [(NSButton *)control setTitle:title];
    } else {
        control.stringValue = title;
    }
}

- (void)testTranslatedTitlesFit {
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        NSDictionary<NSString *, NSString *> *strings = [self stringsForLanguage:language];
        id<ManualAIModelEditorTranslationLayoutForTesting> editor = [self newEditor];
        NSView *content = editor.window.contentView;
        NSMapTable<NSControl *, NSString *> *controls = [self titledControlsOf:content];
        for (NSControl *control in controls) {
            NSString *translation = strings[[controls objectForKey:control]];
            XCTAssertNotNil(translation, @"%@ %@", language, [controls objectForKey:control]);
            [self setTitle:translation ?: @"" of:control];
        }
        XCTAssertTrue([(NSObject *)editor respondsToSelector:@selector(layoutForTranslations)]);
        if (![(NSObject *)editor respondsToSelector:@selector(layoutForTranslations)]) {
            return;
        }
        [editor layoutForTranslations];

        // Every title fits.
        for (NSControl *control in controls) {
            XCTAssertGreaterThanOrEqual(NSWidth(control.frame), ceil(control.cell.cellSize.width),
                                        @"%@ clipped: %@", language, control.stringValue);
        }
        // The right column starts after the widest label, nothing runs out of
        // the window, and the Test button stays clear of Cancel.
        NSTextField *contextField = [(NSObject *)editor valueForKey:@"contextField"];
        NSButton *testButton = [(NSObject *)editor valueForKey:@"testButton"];
        NSProgressIndicator *spinner = [(NSObject *)editor valueForKey:@"testSpinner"];
        for (NSControl *control in controls) {
            if ([control isKindOfClass:NSTextField.class]) {
                XCTAssertLessThanOrEqual(NSMaxX(control.frame), NSMinX(contextField.frame),
                                         @"%@: %@ runs into the fields", language, control.stringValue);
            }
        }
        for (NSView *view in content.subviews) {
            XCTAssertLessThanOrEqual(NSMaxX(view.frame), NSWidth(content.bounds),
                                     @"%@: %@ runs off the window", language, view);
        }
        XCTAssertGreaterThanOrEqual(NSMinX(spinner.frame), NSMaxX(testButton.frame), @"%@", language);
        for (NSView *view in content.subviews) {
            if ([view isKindOfClass:NSButton.class] && view != testButton && NSMinY(view.frame) < 50) {
                XCTAssertLessThanOrEqual(NSMaxX(spinner.frame), NSMinX(view.frame),
                                         @"%@: the Test button runs into %@", language, [(NSButton *)view title]);
            }
        }
    }
}

- (void)testEnglishLayoutIsUnchanged {
    id<ManualAIModelEditorTranslationLayoutForTesting> editor = [self newEditor];
    NSView *content = editor.window.contentView;
    XCTAssertEqual(NSWidth(content.bounds), 590);
    NSTextField *contextField = [(NSObject *)editor valueForKey:@"contextField"];
    XCTAssertEqual(NSMinX(contextField.frame), 182);
    NSButton *testButton = [(NSObject *)editor valueForKey:@"testButton"];
    XCTAssertEqual(NSWidth(testButton.frame), 150);
}

@end
