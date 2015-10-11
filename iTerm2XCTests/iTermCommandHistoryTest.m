//
//  iTermCommandHistoryTest.m
//  iTerm2
//
//  Created by George Nachman on 10/10/15.
//
//

#import <XCTest/XCTest.h>
#import "iTermCommandHistoryController.h"
#import "iTermCommandHistoryEntryMO.h"
#import "VT100RemoteHost.h"

static NSString *const kFakeCommandHistoryPlistPath = @"/tmp/fake_command_history.plist";
static NSString *const kSqlitePathForTest = @"/tmp/test_command_history.sqlite";

@interface iTermCommandHistoryControllerForTesting : iTermCommandHistoryController
@end

@implementation iTermCommandHistoryControllerForTesting

- (NSString *)pathForFileNamed:(NSString *)name {
    if ([name isEqualTo:@"commandhistory.plist"]) {
        return kFakeCommandHistoryPlistPath;
    } else {
        return kSqlitePathForTest;
    }
}

@end
@interface iTermCommandHistoryTest : XCTestCase

@end

@implementation iTermCommandHistoryTest {
    NSTimeInterval _now;
}

- (void)testSuccessfulMigration {
    _now = [NSDate timeIntervalSinceReferenceDate];
    NSDictionary *dictionary =
        @{
            @"user1@host1":
               @[
                   @{
                       @"command": @"command1",
                       @"uses": @10,
                       @"last used": @(_now),
                       @"use times":
                           @[
                               @[ @(_now),
                                  @"/path1",
                                  @"mark-guid-1",
                                  @"command1",
                                ],
                               @[ @(_now - 1),
                                  @"/path2",
                                  @"mark-guid-2",
                                ],
                               @[ @(_now - 2),
                                  @"/path3",
                                ],
                               @[ @(_now - 3) ],
                               @(_now - 4)
                            ],
                    },
                   @{
                       @"command": @"command2",
                       @"uses": @5,
                       @"last used": @(_now),
                       @"use times":
                           @[
                               @[ @(_now),
                                  @"/path4",
                                  @"mark-guid-4",
                                  @"command2",
                                  @1
                                ],
                            ],
                    },
                ],
            @"user2@host2":
                @[
                    @{
                       @"command": @"command3",
                       @"uses": @2,
                       @"last used": @(_now),
                       @"use times":
                           @[
                               @[ @(_now),
                                  @"/path5",
                                  @"mark-guid-5",
                                  @"command3",
                                  @1
                                ],
                               @[ @(_now),
                                  @"/path5",
                                  @"mark-guid-5",
                                  @"command3",
                                  @1
                                  ],
                            ],
                     }
                 ]
           };
    [NSKeyedArchiver archiveRootObject:dictionary toFile:kFakeCommandHistoryPlistPath];
    [[NSFileManager defaultManager] removeItemAtPath:kSqlitePathForTest error:nil];

    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:kFakeCommandHistoryPlistPath isDirectory:nil]);
    iTermCommandHistoryController *historyController = [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:kFakeCommandHistoryPlistPath isDirectory:nil]);
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:kSqlitePathForTest isDirectory:nil]);

    for (int iteration = 0; iteration < 2; iteration++) {
        if (iteration == 1) {
            // Re-create the history controller to verify that values can be loaded
            historyController = [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
        }
        for (NSString *key in dictionary) {
            VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
            NSArray *parts = [key componentsSeparatedByString:@"@"];
            remoteHost.username = parts[0];
            remoteHost.hostname = parts[1];
            NSArray<iTermCommandHistoryEntryMO *> *actualEntries =
                [historyController commandHistoryEntriesWithPrefix:@""
                                                            onHost:remoteHost];
            NSArray *expectedEntries = dictionary[key];
            XCTAssertEqual(expectedEntries.count, actualEntries.count);
            
            for (NSInteger i = 0; i < expectedEntries.count; i++) {
                NSDictionary *expectedEntry = expectedEntries[i];
                iTermCommandHistoryEntryMO *actualEntry = actualEntries[i];
                
                XCTAssertEqualObjects(actualEntry.command, expectedEntry[@"command"]);
                XCTAssertEqualObjects(actualEntry.numberOfUses, expectedEntry[@"uses"]);
                XCTAssertEqualObjects(actualEntry.timeOfLastUse, expectedEntry[@"last used"]);
                XCTAssertEqual(actualEntry.uses.count, [expectedEntry[@"use times"] count]);
                
                NSOrderedSet<iTermCommandHistoryCommandUseMO *> *actualUses = actualEntry.uses;
                for (NSInteger j = 0; j < actualUses.count; j++) {
                    iTermCommandHistoryCommandUseMO *actualUse = actualUses[j];
                    if ([expectedEntry[@"use times"][j] isKindOfClass:[NSArray class]]) {
                        NSArray *expectedUse = expectedEntry[@"use times"][j];
                        XCTAssertEqualObjects(actualUse.time, expectedUse[0]);
                        if (expectedUse.count > 1) {
                            XCTAssertEqualObjects(actualUse.directory, expectedUse[1]);
                        } else {
                            XCTAssertNil(actualUse.directory);
                        }
                        if (expectedUse.count > 2) {
                            XCTAssertEqualObjects(actualUse.markGuid, expectedUse[2]);
                        } else {
                            XCTAssertNil(actualUse.markGuid);
                        }
                        if (expectedUse.count > 3) {
                            XCTAssertEqualObjects(actualUse.command, expectedUse[3]);
                        } else {
                            XCTAssertEqualObjects(actualUse.command, actualEntry.command);
                        }
                        if (expectedUse.count > 4) {
                            XCTAssertEqualObjects(actualUse.code, expectedUse[4]);
                        } else {
                            XCTAssertNil(actualUse.code);
                        }
                    } else {
                        NSNumber *expectedUseTime = expectedEntry[@"use times"][j];
                        XCTAssertEqualObjects(actualUse.time, expectedUseTime);
                    }
                }
            }
        }
    }
}

@end
