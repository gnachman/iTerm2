//
//  ManualAIModelEditorPresetTests.m
//  ModernTests
//
//  Choosing a Preset in the manual AI model editor points the model at a new
//  endpoint, so it must not carry over the custom headers or the API key choice
//  that were set up for the old one. Otherwise a local gateway's bearer token and
//  the OpenAI key are sent to api.anthropic.com after switching to a Claude
//  preset.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "iTermPreferences.h"

// The editor is private to GeneralPreferencesViewController.m. Look it up by
// name and talk to it through this protocol.
@protocol ManualAIModelEditorForTesting <NSObject>
- (instancetype)initWithConfiguration:(NSDictionary *)configuration
                            isEditing:(BOOL)isEditing;
- (void)presetSelected:(NSPopUpButton *)sender;
- (void)saveClicked:(id)sender;
@end

@interface ManualAIModelEditorPresetTests : XCTestCase
@end

@implementation ManualAIModelEditorPresetTests

- (NSDictionary *)gatewayConfiguration {
    return @{
        @"id": NSUUID.UUID.UUIDString,
        @"name": @"my-gateway-model",
        @"url": @"http://192.168.1.10:8080/v1/chat/completions",
        @"api": @0,
        @"contextWindowTokens": @8192,
        @"maxResponseTokens": @1024,
        @"credential": [NSString stringWithFormat:@"vendor:%@", @(iTermAIVendorOpenAI)],
        @"customHeaders": @[ @{ @"name": @"Authorization", @"value": @"Bearer tok" } ],
    };
}

- (id<ManualAIModelEditorForTesting>)editorWithConfiguration:(NSDictionary *)configuration {
    Class editorClass = NSClassFromString(@"iTermManualAIModelEditorController");
    XCTAssertNotNil(editorClass);
    return [[(id)editorClass alloc] initWithConfiguration:configuration isEditing:YES];
}

- (NSPopUpButton *)popupNamed:(NSString *)key ofEditor:(id)editor {
    id popup = [(NSObject *)editor valueForKey:key];
    XCTAssertTrue([popup isKindOfClass:NSPopUpButton.class]);
    return popup;
}

// The tag of the first Claude model in the catalog presets, or -1.
- (NSInteger)claudePresetTagInEditor:(id)editor {
    NSArray *presets = [(NSObject *)editor valueForKey:@"presets"];
    for (NSInteger i = 0; i < (NSInteger)presets.count; i++) {
        if ([[presets[i] valueForKey:@"name"] hasPrefix:@"claude"]) {
            return i;
        }
    }
    return -1;
}

// Selects the preset with the given tag the way a user's click does and saves.
- (NSDictionary *)savedResultAfterChoosingPresetTag:(NSInteger)tag editor:(id<ManualAIModelEditorForTesting>)editor {
    NSPopUpButton *presetPopup = [self popupNamed:@"presetPopup" ofEditor:editor];
    XCTAssertTrue([presetPopup selectItemWithTag:tag]);
    [editor presetSelected:presetPopup];
    [editor saveClicked:nil];
    return [(NSObject *)editor valueForKey:@"result"];
}

- (void)assertLoadedGatewaySettingsInEditor:(id)editor {
    NSArray *headers = [(NSObject *)editor valueForKey:@"headers"];
    XCTAssertEqual(headers.count, 1u, @"Precondition: the header loads into the editor");
    XCTAssertEqual([self popupNamed:@"credentialPopup" ofEditor:editor].selectedTag,
                   (NSInteger)iTermAIVendorOpenAI,
                   @"Precondition: the OpenAI key choice loads into the editor");
}

- (void)testCatalogPresetResetsHeadersAndAPIKeyChoice {
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
    [self assertLoadedGatewaySettingsInEditor:editor];
    const NSInteger tag = [self claudePresetTagInEditor:editor];
    XCTAssertGreaterThanOrEqual(tag, 0, @"The catalog has a Claude preset");

    NSDictionary *result = [self savedResultAfterChoosingPresetTag:tag editor:editor];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"customHeaders"], @[]);
    XCTAssertNil(result[@"credential"], @"Automatic is stored as an absent credential");
    // -1 is kAICredentialTagAutomatic.
    XCTAssertEqual([self popupNamed:@"credentialPopup" ofEditor:editor].selectedTag, -1,
                   @"The popup shows Automatic");
    XCTAssertEqual(((NSTableView *)[(NSObject *)editor valueForKey:@"headersTable"]).numberOfRows, 0,
                   @"The headers table shows the cleared headers");
}

// A key typed for the old endpoint must not reappear if the user picks “This
// model’s own key” after choosing a preset.
- (void)testPresetClearsModelOwnKeyField {
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
    NSTextField *keyField = [(NSObject *)editor valueForKey:@"modelAPIKeyField"];
    keyField.stringValue = @"gateway-key";
    NSPopUpButton *presetPopup = [self popupNamed:@"presetPopup" ofEditor:editor];
    XCTAssertTrue([presetPopup selectItemWithTag:[self claudePresetTagInEditor:editor]]);
    [editor presetSelected:presetPopup];

    XCTAssertEqualObjects(keyField.stringValue, @"");
}

- (void)testProviderPresetResetsHeadersAndAPIKeyChoice {
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
    [self assertLoadedGatewaySettingsInEditor:editor];
    NSArray *providerPresets = [(NSObject *)editor valueForKey:@"providerPresets"];
    NSInteger providerIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)providerPresets.count; i++) {
        if (![[providerPresets[i] valueForKey:@"dynamicModels"] boolValue]) {
            providerIndex = i;
            break;
        }
    }
    XCTAssertGreaterThanOrEqual(providerIndex, 0, @"There is a provider preset that names a model");
    NSPopUpButton *presetPopup = [self popupNamed:@"presetPopup" ofEditor:editor];
    // Provider presets are tagged kAIProviderPresetTagBase + index.
    const NSInteger tag = 100000 + providerIndex;
    XCTAssertTrue([presetPopup selectItemWithTag:tag]);
    [editor presetSelected:presetPopup];
    // Provider presets clear the model name, so supply one before saving.
    ((NSTextField *)[(NSObject *)editor valueForKey:@"nameField"]).stringValue = @"some-model";
    [editor saveClicked:nil];
    NSDictionary *result = [(NSObject *)editor valueForKey:@"result"];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"customHeaders"], @[]);
    XCTAssertNil(result[@"credential"]);
}

- (void)testSavingWithoutAPresetKeepsHeadersAndAPIKeyChoice {
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
    [editor saveClicked:nil];
    NSDictionary *result = [(NSObject *)editor valueForKey:@"result"];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"customHeaders"], (@[ @{ @"name": @"Authorization", @"value": @"Bearer tok" } ]));
    XCTAssertEqualObjects(result[@"credential"], ([NSString stringWithFormat:@"vendor:%@", @(iTermAIVendorOpenAI)]));
}

@end
