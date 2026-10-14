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
    XCTAssertEqualObjects(result[@"credential"], @"automatic");
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

// Selects the provider preset at `index` the way a user's click does, names a
// model (provider presets clear the name), and saves.
- (NSDictionary *)savedResultAfterChoosingProviderPresetIndex:(NSInteger)providerIndex
                                                       editor:(id<ManualAIModelEditorForTesting>)editor {
    NSPopUpButton *presetPopup = [self popupNamed:@"presetPopup" ofEditor:editor];
    // Provider presets are tagged kAIProviderPresetTagBase + index.
    const NSInteger tag = 100000 + providerIndex;
    XCTAssertTrue([presetPopup selectItemWithTag:tag]);
    [editor presetSelected:presetPopup];
    ((NSTextField *)[(NSObject *)editor valueForKey:@"nameField"]).stringValue = @"some-model";
    [editor saveClicked:nil];
    return [(NSObject *)editor valueForKey:@"result"];
}

// A provider preset is a third-party gateway (or a local server), which no
// vendor's stored key belongs to, so the key choice resets to None rather than
// Automatic: the user picks the gateway's key explicitly.
- (void)testProviderPresetResetsHeadersAndSelectsNoKey {
    NSArray *providerPresets = [(NSObject *)[self editorWithConfiguration:[self gatewayConfiguration]]
                                valueForKey:@"providerPresets"];
    NSInteger checked = 0;
    for (NSInteger i = 0; i < (NSInteger)providerPresets.count; i++) {
        if ([[providerPresets[i] valueForKey:@"dynamicModels"] boolValue]) {
            // Auto-discovery disables the key popup; covered below.
            continue;
        }
        id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
        [self assertLoadedGatewaySettingsInEditor:editor];
        NSDictionary *result = [self savedResultAfterChoosingProviderPresetIndex:i editor:editor];
        NSString *name = [providerPresets[i] valueForKey:@"name"];

        XCTAssertNotNil(result, @"%@", name);
        XCTAssertEqualObjects(result[@"customHeaders"], @[], @"%@", name);
        XCTAssertEqualObjects(result[@"credential"], @"none", @"%@", name);
        // -3 is kAICredentialTagNone.
        XCTAssertEqual([self popupNamed:@"credentialPopup" ofEditor:editor].selectedTag, -3, @"%@", name);
        checked++;
    }
    XCTAssertGreaterThan(checked, 0, @"There is a provider preset that names a model");
}

// The finding's scenario: a model whose key choice was None must not start
// sending the OpenAI key to OpenRouter just because its preset was chosen.
- (void)testOpenRouterPresetDoesNotTurnNoneIntoAKey {
    NSMutableDictionary *configuration = [[self gatewayConfiguration] mutableCopy];
    configuration[@"credential"] = @"none";
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:configuration];
    NSArray *providerPresets = [(NSObject *)editor valueForKey:@"providerPresets"];
    NSInteger openRouterIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)providerPresets.count; i++) {
        if ([[providerPresets[i] valueForKey:@"url"] containsString:@"openrouter.ai"]) {
            openRouterIndex = i;
        }
    }
    XCTAssertGreaterThanOrEqual(openRouterIndex, 0, @"There is an OpenRouter preset");
    NSDictionary *result = [self savedResultAfterChoosingProviderPresetIndex:openRouterIndex editor:editor];

    XCTAssertEqualObjects(result[@"credential"], @"none");
}

// Auto-discovering presets authorize the automatic way (the popup is disabled),
// which for their local server means no key.
- (void)testDynamicProviderPresetStoresAutomatic {
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:[self gatewayConfiguration]];
    NSArray *providerPresets = [(NSObject *)editor valueForKey:@"providerPresets"];
    NSInteger dynamicIndex = -1;
    for (NSInteger i = 0; i < (NSInteger)providerPresets.count; i++) {
        if ([[providerPresets[i] valueForKey:@"dynamicModels"] boolValue]) {
            dynamicIndex = i;
            break;
        }
    }
    XCTAssertGreaterThanOrEqual(dynamicIndex, 0, @"There is an auto-discovering preset");
    NSPopUpButton *presetPopup = [self popupNamed:@"presetPopup" ofEditor:editor];
    XCTAssertTrue([presetPopup selectItemWithTag:100000 + dynamicIndex]);
    [editor presetSelected:presetPopup];
    [editor saveClicked:nil];
    NSDictionary *result = [(NSObject *)editor valueForKey:@"result"];

    XCTAssertNotNil(result);
    XCTAssertEqualObjects(result[@"credential"], @"automatic");
}

// A configuration saved by an older build has no stored key choice, and there
// Automatic sent the OpenAI key to any host. The editor shows that choice
// explicitly, and saving keeps it, rather than silently switching the gateway
// to the host-bound Automatic.
- (void)testOlderGatewayConfigurationShowsTheKeyItSends {
    NSMutableDictionary *configuration = [[self gatewayConfiguration] mutableCopy];
    configuration[@"url"] = @"https://openrouter.ai/api/v1/chat/completions";
    [configuration removeObjectForKey:@"credential"];
    id<ManualAIModelEditorForTesting> editor = [self editorWithConfiguration:configuration];
    XCTAssertEqual([self popupNamed:@"credentialPopup" ofEditor:editor].selectedTag,
                   (NSInteger)iTermAIVendorOpenAI);
    [editor saveClicked:nil];
    NSDictionary *result = [(NSObject *)editor valueForKey:@"result"];
    XCTAssertEqualObjects(result[@"credential"], ([NSString stringWithFormat:@"vendor:%@", @(iTermAIVendorOpenAI)]));
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
