//
//  LegacyManualAIModelHeadersTests.m
//  ModernTests
//
//  A user with a single legacy manual model (no model configurations) whose
//  requests carry the former global custom headers must keep sending them
//  after opening the models panel, which turns the legacy model into a
//  configuration. Saving that configuration retires the global headers, so
//  they must be copied into it.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "GeneralPreferencesViewController.h"
#import "iTermPreferences.h"
#import "iTermUserDefaults.h"

@interface GeneralPreferencesViewController (LegacyManualAIModelHeadersTests)
- (NSMutableArray<NSMutableDictionary *> *)mutableManualAIModelConfigurations;
@end

@interface LegacyManualAIModelHeadersTests : XCTestCase
@end

@implementation LegacyManualAIModelHeadersTests {
    NSDictionary<NSString *, id> *_saved;
    id _savedDone;
}

static NSString *const kDoneKey = @"NoSyncAICustomHeadersPerModelMigrationDone";

- (NSArray<NSString *> *)keys {
    return @[ kPreferenceKeyAIManualModelConfigurations,
              kPreferenceKeyUseRecommendedAIModel,
              kPreferenceKeyAITermURL,
              kPreferenceKeyAICustomHeadersEnabled,
              kPreferenceKeyAICustomHeaders ];
}

- (void)setUp {
    [super setUp];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in self.keys) {
        saved[key] = [iTermPreferences objectForKey:key] ?: [NSNull null];
    }
    _saved = saved;
    _savedDone = [[iTermUserDefaults userDefaults] objectForKey:kDoneKey];
}

- (void)tearDown {
    for (NSString *key in self.keys) {
        id value = _saved[key];
        [iTermPreferences setObject:[value isKindOfClass:[NSNull class]] ? nil : value forKey:key];
    }
    [[iTermUserDefaults userDefaults] setObject:_savedDone forKey:kDoneKey];
    [super tearDown];
}

- (void)testLegacyModelCarriesGlobalHeaders {
    [iTermPreferences setObject:@[] forKey:kPreferenceKeyAIManualModelConfigurations];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyUseRecommendedAIModel];
    [iTermPreferences setObject:@"http://localhost:8080/v1/chat/completions" forKey:kPreferenceKeyAITermURL];
    [iTermPreferences setBool:YES forKey:kPreferenceKeyAICustomHeadersEnabled];
    [iTermPreferences setObject:@[ @{ @"name": @"X-Old", @"value": @"v" }, @"junk" ]
                         forKey:kPreferenceKeyAICustomHeaders];
    [[iTermUserDefaults userDefaults] setBool:YES forKey:kDoneKey];

    GeneralPreferencesViewController *vc = [[GeneralPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    NSArray<NSDictionary *> *configs = [vc mutableManualAIModelConfigurations];

    XCTAssertEqual(configs.count, 1u);
    XCTAssertEqualObjects(configs.firstObject[@"customHeaders"],
                          (@[ @{ @"name": @"X-Old", @"value": @"v" } ]));
}

- (void)testLegacyModelHasNoHeadersWhenGlobalHeadersDisabled {
    [iTermPreferences setObject:@[] forKey:kPreferenceKeyAIManualModelConfigurations];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyUseRecommendedAIModel];
    [iTermPreferences setObject:@"http://localhost:8080/v1/chat/completions" forKey:kPreferenceKeyAITermURL];
    [iTermPreferences setBool:NO forKey:kPreferenceKeyAICustomHeadersEnabled];
    [iTermPreferences setObject:@[ @{ @"name": @"X-Old", @"value": @"v" } ]
                         forKey:kPreferenceKeyAICustomHeaders];
    [[iTermUserDefaults userDefaults] setBool:YES forKey:kDoneKey];

    GeneralPreferencesViewController *vc = [[GeneralPreferencesViewController alloc] initWithNibName:nil bundle:nil];
    NSArray<NSDictionary *> *configs = [vc mutableManualAIModelConfigurations];

    XCTAssertEqual(configs.count, 1u);
    XCTAssertEqualObjects(configs.firstObject[@"customHeaders"], @[]);
}

@end
