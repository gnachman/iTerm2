//
//  DynamicProfileErrorCountTests.m
//  ModernTests
//
//  When several Dynamic Profiles files are bad, the alert shows the first problem and says how
//  many more are in the log. The “Ignoring dynamic profiles in … because of an error.” line logged
//  after each bad file was counted as another error, so N bad files reported 2N-1 additional
//  errors instead of N-1 (QA finding F-301).
//

#import <XCTest/XCTest.h>

#import "iTermDynamicProfileManager.h"
#import "iTermWarning.h"

@interface DynamicProfileErrorCountWarningHandler : NSObject<iTermWarningHandler>
@property (nonatomic, strong) NSMutableArray<NSString *> *messages;
@end

@implementation DynamicProfileErrorCountWarningHandler
- (instancetype)init {
    self = [super init];
    if (self) {
        _messages = [NSMutableArray array];
    }
    return self;
}

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    [self.messages addObject:alert.informativeText ?: @""];
    return NSAlertFirstButtonReturn;
}
@end

@interface DynamicProfileErrorCountTests : XCTestCase
@end

@implementation DynamicProfileErrorCountTests {
    NSString *_directory;
    id<iTermWarningHandler> _savedHandler;
    DynamicProfileErrorCountWarningHandler *_handler;
}

- (void)setUp {
    [super setUp];
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"DynamicProfileErrorCountTests-%@", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    _savedHandler = [iTermWarning warningHandler];
    _handler = [[DynamicProfileErrorCountWarningHandler alloc] init];
    [iTermWarning setWarningHandler:_handler];
    [iTermWarning unsilenceIdentifier:@"NoSyncDynamicProfilesWarning"];
    // Let any error alert already queued by someone else go by before counting.
    [self drainMainQueue];
    [_handler.messages removeAllObjects];
}

- (void)tearDown {
    [self drainMainQueue];
    [iTermWarning setWarningHandler:_savedHandler];
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:nil];
    [super tearDown];
}

// Errors are shown from a block dispatched to the main queue. Main queue blocks run in order, so
// once this one has run, they have too.
- (void)drainMainQueue {
    XCTestExpectation *drained = [self expectationWithDescription:@"main queue drained"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [drained fulfill];
    });
    [self waitForExpectations:@[ drained ] timeout:10];
}

- (NSString *)writeFile:(NSString *)name contents:(NSString *)contents {
    NSString *path = [_directory stringByAppendingPathComponent:name];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (void)testAdditionalErrorCountIsTheNumberOfOtherProblems {
    NSArray<NSString *> *paths = @[ [self writeFile:@"a.json" contents:@"{"],
                                    [self writeFile:@"b.json" contents:@"[]"],
                                    [self writeFile:@"c.json" contents:@"{\"Profiles\":5}"] ];
    iTermDynamicProfileManager *manager = [iTermDynamicProfileManager sharedInstance];
    NSMutableArray *profiles = [NSMutableArray array];
    NSMutableSet *guids = [NSMutableSet set];
    for (NSString *path in paths) {
        [manager loadDynamicProfilesFromFileLoggingFailure:path intoArray:profiles guids:guids];
    }
    [self drainMainQueue];

    XCTAssertEqual(_handler.messages.count, 1, @"%@", _handler.messages);
    NSString *message = _handler.messages.firstObject;
    XCTAssertTrue([message containsString:@"2 additional errors"], @"%@", message);
    XCTAssertEqual(profiles.count, 0);
}

// The folder watcher can reload twice before the alert is shown, such as when two bad files
// appear at once. Each reload re-examines every file, so the second reload's errors replace the
// first's instead of adding to them (QA finding F-421).
- (void)testBackToBackReloadsDoNotDoubleCountErrors {
    NSArray<NSString *> *paths = @[ [self writeFile:@"x.json" contents:@"{"],
                                    [self writeFile:@"y.json" contents:@"[]"] ];
    iTermDynamicProfileManager *manager = [iTermDynamicProfileManager sharedInstance];
    for (int i = 0; i < 2; i++) {
        [manager performReloadPass:^{
            NSMutableArray *profiles = [NSMutableArray array];
            NSMutableSet *guids = [NSMutableSet set];
            for (NSString *path in paths) {
                [manager loadDynamicProfilesFromFileLoggingFailure:path intoArray:profiles guids:guids];
            }
        }];
    }
    [self drainMainQueue];

    XCTAssertEqual(_handler.messages.count, 1, @"%@", _handler.messages);
    NSString *message = _handler.messages.firstObject;
    XCTAssertTrue([message containsString:@"1 additional error"], @"%@", message);
    XCTAssertFalse([message containsString:@"3 additional errors"], @"%@", message);
}

// If a later reload finds nothing wrong (the files were fixed) before the alert is shown, there is
// nothing to report.
- (void)testReloadWithoutErrorsCancelsThePendingAlert {
    NSString *bad = [self writeFile:@"z.json" contents:@"{"];
    iTermDynamicProfileManager *manager = [iTermDynamicProfileManager sharedInstance];
    [manager performReloadPass:^{
        [manager loadDynamicProfilesFromFileLoggingFailure:bad
                                                 intoArray:[NSMutableArray array]
                                                     guids:[NSMutableSet set]];
    }];
    [manager performReloadPass:^{}];
    [self drainMainQueue];

    XCTAssertEqual(_handler.messages.count, 0, @"%@", _handler.messages);
}

@end
