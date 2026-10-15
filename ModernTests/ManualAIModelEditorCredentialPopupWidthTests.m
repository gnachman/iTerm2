//
//  ManualAIModelEditorCredentialPopupWidthTests.m
//  ModernTests
//
//  QA finding F-338: in the manual AI model editor, the API key popup was a
//  fixed 210 points wide, so with a local endpoint its “Automatic (none for a
//  local endpoint)” choice read “Automatic (none for a local…”, and longer
//  still in other languages. These check that the popup shows its selected
//  choice in full and that the key field beside it still has room when it's
//  needed.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

@protocol ManualAIModelEditorCredentialPopupForTesting <NSObject>
- (instancetype)initWithConfiguration:(NSDictionary *)configuration isEditing:(BOOL)isEditing;
- (void)sizeCredentialPopupToFit;
- (void)credentialPopupDidChange:(id)sender;
@property(nonatomic, readonly) NSWindow *window;
@end

@interface ManualAIModelEditorCredentialPopupWidthTests : XCTestCase
@end

@implementation ManualAIModelEditorCredentialPopupWidthTests

- (id<ManualAIModelEditorCredentialPopupForTesting>)newLocalEditor {
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    XCTAssertNotNil(editorClass);
    NSDictionary *configuration = @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": @"some-model",
        @"url": @"http://127.0.0.1:9/v1/chat/completions",
        @"api": @1,
        @"contextWindowTokens": @8192,
        @"maxResponseTokens": @1024,
        @"credential": @"automatic",
    };
    return [[editorClass alloc] initWithConfiguration:configuration isEditing:YES];
}

- (NSPopUpButton *)popupOf:(id)editor {
    return [(NSObject *)editor valueForKey:@"credentialPopup"];
}

- (NSTextField *)keyFieldOf:(id)editor {
    return [(NSObject *)editor valueForKey:@"modelAPIKeyField"];
}

// The width a popup like the editor's needs to show `title` in full.
- (CGFloat)widthNeededBy:(NSPopUpButton *)popup toShow:(NSString *)title {
    NSPopUpButton *measure = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    measure.font = popup.font;
    [measure addItemWithTitle:title];
    return ceil(measure.cell.cellSize.width);
}

- (void)assertPopupFitsIn:(id)editor rowEnd:(CGFloat)rowEnd label:(NSString *)label {
    NSPopUpButton *popup = [self popupOf:editor];
    XCTAssertGreaterThanOrEqual(NSWidth(popup.frame), [self widthNeededBy:popup toShow:popup.titleOfSelectedItem],
                                @"%@: “%@” clipped", label, popup.titleOfSelectedItem);
    XCTAssertLessThanOrEqual(NSMaxX(popup.frame), rowEnd, @"%@: the popup runs past its row", label);
}

- (void)testEnglishLocalEndpointChoiceFits {
    id<ManualAIModelEditorCredentialPopupForTesting> editor = [self newLocalEditor];
    NSPopUpButton *popup = [self popupOf:editor];
    XCTAssertEqualObjects(popup.titleOfSelectedItem, @"Automatic (none for a local endpoint)");
    // Guards the premise: it needs more than the old fixed width.
    XCTAssertGreaterThan([self widthNeededBy:popup toShow:popup.titleOfSelectedItem], 210);
    [self assertPopupFitsIn:editor rowEnd:NSMaxX([self keyFieldOf:editor].frame) label:@"en"];
}

- (void)testKeyFieldGetsItsRoomBack {
    id<ManualAIModelEditorCredentialPopupForTesting> editor = [self newLocalEditor];
    NSPopUpButton *popup = [self popupOf:editor];
    NSTextField *keyField = [self keyFieldOf:editor];
    const CGFloat rowEnd = NSMaxX(keyField.frame);
    [popup selectItemWithTag:-2];  // This model’s own key
    [editor credentialPopupDidChange:popup];
    XCTAssertFalse(keyField.hidden);
    XCTAssertEqual(NSWidth(popup.frame), 210);
    XCTAssertGreaterThanOrEqual(NSMinX(keyField.frame), NSMaxX(popup.frame));
    XCTAssertEqual(NSMaxX(keyField.frame), rowEnd);
}

- (void)testTranslatedAutomaticChoicesFit {
    NSArray<NSString *> *keys = @[ @"AIModelEditor.AutomaticNoKeyLocal",
                                   @"AIModelEditor.AutomaticNoKeyUnrecognizedHost",
                                   @"AIModelEditor.AutomaticNoKey" ];
    for (NSString *language in @[ @"de", @"ja", @"pt-BR", @"ru", @"zh-Hans" ]) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"Localizable"
                                                         ofType:@"strings"
                                                    inDirectory:nil
                                                forLocalization:language];
        NSDictionary<NSString *, NSString *> *strings = [NSDictionary dictionaryWithContentsOfFile:path];
        for (NSString *key in keys) {
            XCTAssertNotNil(strings[key], @"%@ %@", language, key);
            id<ManualAIModelEditorCredentialPopupForTesting> editor = [self newLocalEditor];
            NSPopUpButton *popup = [self popupOf:editor];
            const CGFloat rowEnd = NSMaxX([self keyFieldOf:editor].frame);
            popup.selectedItem.title = strings[key] ?: @"";
            [popup synchronizeTitleAndSelectedItem];
            [editor sizeCredentialPopupToFit];
            [self assertPopupFitsIn:editor rowEnd:rowEnd label:language];
        }
    }
}

@end
