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
#import "iTermCommandHistoryMO.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"

static NSString *const kFakeCommandHistoryPlistPath = @"/tmp/fake_command_history.plist";
static NSString *const kSqlitePathForTest = @"/tmp/test_command_history.sqlite";

@interface iTermCommandHistoryControllerForTesting : iTermCommandHistoryController
@property(nonatomic) NSTimeInterval currentTime;
@end

@implementation iTermCommandHistoryControllerForTesting

- (NSString *)pathForFileNamed:(NSString *)name {
    if ([name isEqualTo:@"commandhistory.plist"]) {
        return kFakeCommandHistoryPlistPath;
    } else {
        return kSqlitePathForTest;
    }
}

- (NSTimeInterval)now {
    return self.currentTime;
}

@end
@interface iTermCommandHistoryTest : XCTestCase

@end

@implementation iTermCommandHistoryTest {
    NSTimeInterval _now;
}

- (void)setUp {
    [[NSFileManager defaultManager] removeItemAtPath:kSqlitePathForTest error:nil];

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

    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:kFakeCommandHistoryPlistPath isDirectory:nil]);
    iTermCommandHistoryController *historyController =
        [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
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

- (void)testAddFirstCommandOnNewHost {
    iTermCommandHistoryControllerForTesting *historyController =
        [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    const NSTimeInterval now = 1000000;
    historyController.currentTime = now;

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray *entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 0);
    
    VT100ScreenMark *mark = [[[VT100ScreenMark alloc] init] autorelease];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory1"
                         withMark:mark];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);
    
    iTermCommandHistoryEntryMO *entry = entries[0];
    XCTAssertEqualObjects([entry command], @"command1");
    XCTAssertEqualObjects([entry numberOfUses], @1);
    XCTAssertEqualObjects([entry timeOfLastUse], @(now));
    XCTAssertEqual([entry.uses count], 1);
    XCTAssertEqualObjects([entry.remoteHost hostname], remoteHost.hostname);
    XCTAssertEqualObjects([entry.remoteHost username], remoteHost.username);
    
    iTermCommandHistoryCommandUseMO *use = entry.uses[0];
    XCTAssertEqualObjects(use.markGuid, mark.guid);
    XCTAssertEqualObjects(use.directory, @"/directory1");
    XCTAssertEqualObjects(use.time, @(now));
    XCTAssertEqualObjects(use.command, @"command1");
    XCTAssertNil(use.code);
    XCTAssertEqualObjects(use.entry, entry);
}

- (void)testAddAdditionalUseOfCommand {
    iTermCommandHistoryControllerForTesting *historyController =
        [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    const NSTimeInterval time1 = 1000000;
    const NSTimeInterval time2 = 1000001;
    historyController.currentTime = time1;

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray *entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 0);
    
    VT100ScreenMark *mark1 = [[[VT100ScreenMark alloc] init] autorelease];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory1"
                         withMark:mark1];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);

    historyController.currentTime = time2;
    VT100ScreenMark *mark2 = [[[VT100ScreenMark alloc] init] autorelease];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory2"
                         withMark:mark2];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);

    // Check entry
    iTermCommandHistoryEntryMO *entry = entries[0];
    XCTAssertEqualObjects([entry command], @"command1");
    XCTAssertEqualObjects([entry numberOfUses], @2);
    XCTAssertEqualObjects([entry timeOfLastUse], @(time2));
    XCTAssertEqual([entry.uses count], 2);
    XCTAssertEqualObjects([entry.remoteHost hostname], remoteHost.hostname);
    XCTAssertEqualObjects([entry.remoteHost username], remoteHost.username);
    
    // Check first use
    iTermCommandHistoryCommandUseMO *use = entry.uses[0];
    XCTAssertEqualObjects(use.markGuid, mark1.guid);
    XCTAssertEqualObjects(use.directory, @"/directory1");
    XCTAssertEqualObjects(use.time, @(time1));
    XCTAssertEqualObjects(use.command, @"command1");
    XCTAssertNil(use.code);
    XCTAssertEqualObjects(use.entry, entry);
    
    // Check second use
    use = entry.uses[1];
    XCTAssertEqualObjects(use.markGuid, mark2.guid);
    XCTAssertEqualObjects(use.directory, @"/directory2");
    XCTAssertEqualObjects(use.time, @(time2));
    XCTAssertEqualObjects(use.command, @"command1");
    XCTAssertNil(use.code);
    XCTAssertEqualObjects(use.entry, entry);
}

- (void)testSetStatusOfCommand {
    iTermCommandHistoryControllerForTesting *historyController =
        [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    const NSTimeInterval now = 1000000;
    historyController.currentTime = now;

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray *entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 0);
    
    VT100ScreenMark *mark = [[[VT100ScreenMark alloc] init] autorelease];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory1"
                         withMark:mark];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);
    
    iTermCommandHistoryEntryMO *entry = entries[0];
    iTermCommandHistoryCommandUseMO *use = entry.uses[0];
    XCTAssertEqualObjects(use.markGuid, mark.guid);
    XCTAssertEqualObjects(use.directory, @"/directory1");
    XCTAssertEqualObjects(use.time, @(now));
    XCTAssertEqualObjects(use.command, @"command1");
    XCTAssertNil(use.code);
    XCTAssertEqualObjects(use.entry, entry);
    
    [historyController setStatusOfCommandAtMark:mark onHost:remoteHost to:123];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);
    
    entry = entries[0];
    use = entry.uses[0];
    XCTAssertEqualObjects(use.markGuid, mark.guid);
    XCTAssertEqualObjects(use.directory, @"/directory1");
    XCTAssertEqualObjects(use.time, @(now));
    XCTAssertEqualObjects(use.command, @"command1");
    XCTAssertEqualObjects(use.code, @123);
    XCTAssertEqualObjects(use.entry, entry);
}

- (NSArray *)commandWithCommonPrefixes {
    return @[ @"abc", @"abcd", @"a", @"bcd", @"", @"abc" ];
}
- (VT100RemoteHost *)addEntriesWithCommonPrefixes:(iTermCommandHistoryControllerForTesting *)historyController {
    const NSTimeInterval now = 1000000;
    historyController.currentTime = now;

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray *entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 0);

    historyController.currentTime = 0;
    for (NSString *command in self.commandWithCommonPrefixes) {
        VT100ScreenMark *mark = [[[VT100ScreenMark alloc] init] autorelease];
        [historyController addCommand:command
                               onHost:remoteHost
                          inDirectory:@"/directory1"
                             withMark:mark];
        historyController.currentTime = historyController.currentTime + 1;
    }
    VT100RemoteHost *bogusHost = [[[VT100RemoteHost alloc] init] autorelease];
    bogusHost.username = @"bogus";
    bogusHost.hostname = @"bogus";
    [historyController addCommand:@"aaaa"
                           onHost:bogusHost
                      inDirectory:@"/directory1"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    return remoteHost;
}

- (void)testSearchEntriesByPrefix {
    iTermCommandHistoryControllerForTesting *historyController =
        [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    VT100RemoteHost *remoteHost = [self addEntriesWithCommonPrefixes:historyController];
    NSArray *entries;
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, self.commandWithCommonPrefixes.count - 1);
    entries = [historyController commandHistoryEntriesWithPrefix:@"a" onHost:remoteHost];
    XCTAssertEqual(entries.count, 3);
    entries = [historyController commandHistoryEntriesWithPrefix:@"b" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);
    entries = [historyController commandHistoryEntriesWithPrefix:@"c" onHost:remoteHost];
    XCTAssertEqual(entries.count, 0);
}

- (void)testSearchUsesByPrefix {
    iTermCommandHistoryControllerForTesting *historyController =
    [[[iTermCommandHistoryControllerForTesting alloc] init] autorelease];
    VT100RemoteHost *remoteHost = [self addEntriesWithCommonPrefixes:historyController];
    NSArray *uses;
    uses = [historyController autocompleteSuggestionsWithPartialCommand:@"" onHost:remoteHost];
    XCTAssertEqual(uses.count, self.commandWithCommonPrefixes.count - 1);
    // Make sure "abc" has a time of 5, meaning it's the new one.
    BOOL found = NO;
    for (iTermCommandHistoryCommandUseMO *use in uses) {
        if ([use.command isEqualTo:@"abc"]) {
            XCTAssertEqual(5.0, round(use.time.doubleValue));
            found = YES;
        }
    }
    XCTAssert(found);
    
    uses = [historyController autocompleteSuggestionsWithPartialCommand:@"a" onHost:remoteHost];
    XCTAssertEqual(uses.count, 3);
    uses = [historyController autocompleteSuggestionsWithPartialCommand:@"b" onHost:remoteHost];
    XCTAssertEqual(uses.count, 1);
    uses = [historyController autocompleteSuggestionsWithPartialCommand:@"c" onHost:remoteHost];
    XCTAssertEqual(uses.count, 0);
    
}

@end
