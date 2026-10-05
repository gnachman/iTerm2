//
//  DynamicProfileMalformedJSONTests.m
//  ModernTests
//
//  Dynamic Profiles files are written by hand or by scripts, so their values can be any JSON type.
//  -[iTermDynamicProfileManager profilesInFile:fileType:] trusted the types and crashed on:
//  "Profiles" not being an array, an entry not being a dictionary, a "Keyboard Map" that is an
//  array (the deprecated key mapping check subscripted it), and JSON null values (a null parent
//  name reached bookmarkWithName:, and any null made the NSUserDefaults write throw "Attempt to
//  insert non-property list object"). Bad values must be reported and skipped, not crash.
//

#import <XCTest/XCTest.h>

#import "ITAddressBookMgr.h"
#import "iTermDynamicProfileManager.h"
#import "iTermWarning.h"

@interface DynamicProfileMalformedJSONWarningHandler : NSObject<iTermWarningHandler>
@end

@implementation DynamicProfileMalformedJSONWarningHandler
- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    return NSAlertFirstButtonReturn;
}
@end

@interface DynamicProfileMalformedJSONTests : XCTestCase
@end

@implementation DynamicProfileMalformedJSONTests {
    NSString *_path;
    id<iTermWarningHandler> _savedHandler;
    DynamicProfileMalformedJSONWarningHandler *_handler;
}

- (void)setUp {
    [super setUp];
    _path = [NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat:@"DynamicProfileMalformedJSONTests-%@.json", [[NSUUID UUID] UUIDString]]];
    // Errors are reported with a modal warning; answer it instead of blocking the test.
    _savedHandler = [iTermWarning warningHandler];
    _handler = [[DynamicProfileMalformedJSONWarningHandler alloc] init];
    [iTermWarning setWarningHandler:_handler];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_path error:nil];
    // Errors are shown from a block dispatched to the main queue. Let those run while the handler
    // is still installed; main queue blocks run in order, so this one runs after them.
    XCTestExpectation *drained = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:10];
    [iTermWarning setWarningHandler:_savedHandler];
    [super tearDown];
}

- (NSArray<Profile *> *)profilesFromJSON:(NSString *)json {
    [json writeToFile:_path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    __block NSArray<Profile *> *result = nil;
    XCTAssertNoThrow(result = [[iTermDynamicProfileManager sharedInstance] profilesInFile:_path fileType:nil]);
    return result;
}

static BOOL ContainsNull(id object) {
    if ([object isKindOfClass:[NSNull class]]) {
        return YES;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        for (id value in [object allValues]) {
            if (ContainsNull(value)) {
                return YES;
            }
        }
    }
    if ([object isKindOfClass:[NSArray class]]) {
        for (id value in object) {
            if (ContainsNull(value)) {
                return YES;
            }
        }
    }
    return NO;
}

- (void)testProfilesThatIsNotAnArray {
    NSArray *profiles = [self profilesFromJSON:@"{\"Profiles\": \"oops\"}"];
    XCTAssertEqual(profiles.count, 0);
}

- (void)testEntryThatIsNotADictionaryIsSkipped {
    NSArray *profiles = [self profilesFromJSON:
        @"{\"Profiles\": [\"oops\", {\"Guid\": \"dp-malformed-1\", \"Name\": \"Good\"}]}"];
    XCTAssertEqualObjects([profiles valueForKey:KEY_GUID], @[ @"dp-malformed-1" ]);
}

- (void)testKeyboardMapThatIsNotADictionaryIsDropped {
    NSArray<Profile *> *profiles = [self profilesFromJSON:
        @"{\"Profiles\": [{\"Guid\": \"dp-malformed-2\", \"Name\": \"Keys\", \"Keyboard Map\": []}]}"];
    XCTAssertEqual(profiles.count, 1);
    id map = profiles.firstObject[KEY_KEYBOARD_MAP];
    XCTAssertTrue(map == nil || [map isKindOfClass:[NSDictionary class]], @"%@", map);
}

- (void)testNullValuesAreRemoved {
    NSArray<Profile *> *profiles = [self profilesFromJSON:
        @"{\"Profiles\": [{\"Guid\": \"dp-malformed-3\", \"Name\": \"Nulls\", "
        @"\"Tab Color\": null, \"Dynamic Profile Parent Name\": null, "
        @"\"Ansi 0 Color\": {\"Red Component\": 0, \"Alpha Component\": null}}]}"];
    XCTAssertEqual(profiles.count, 1);
    XCTAssertFalse(ContainsNull(profiles.firstObject), @"%@", profiles.firstObject);
    XCTAssertEqualObjects(profiles.firstObject[KEY_NAME], @"Nulls");
}

@end
