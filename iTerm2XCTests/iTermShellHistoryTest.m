//
//  iTermCommandHistoryTest.m
//  iTerm2
//
//  Created by George Nachman on 10/10/15.
//
//

#import <XCTest/XCTest.h>
#import "iTermCommandHistoryEntryMO.h"
#import "iTermHostRecordMO.h"
#import "iTermShellHistoryController.h"
#import "NSStringITerm.h"
#import "VT100RemoteHost.h"
#import "VT100ScreenMark.h"

static NSString *const kFakeCommandHistoryPlistPath = @"/tmp/fake_command_history.plist";
static NSString *const kFakeDirectoriesPlistPath = @"/tmp/fake_directories.plist";
static NSString *const kSqlitePathForTest = @"/tmp/test_command_history.sqlite";
static NSTimeInterval kDefaultTime = 10000000;

@interface iTermShellHistoryControllerForTesting : iTermShellHistoryController
@property(nonatomic) NSTimeInterval currentTime;
@property(nonatomic, copy) NSString *guid;

- (instancetype)initWithGuid:(NSString *)guid NS_DESIGNATED_INITIALIZER;

@end

@implementation iTermShellHistoryControllerForTesting

- (instancetype)initWithGuid:(NSString *)guid {
    self = [super initPartially];
    if (self) {
        self.guid = guid;
        if (![self finishInitialization]) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc {
    [_guid release];
    [super dealloc];
}

- (NSString *)pathForFileNamed:(NSString *)name {
    if ([name isEqualTo:@"commandhistory.plist"]) {
        return [kFakeCommandHistoryPlistPath stringByAppendingString:self.guid];
    } else if ([name isEqualTo:@"directories.plist"]) {
        return [kFakeDirectoriesPlistPath stringByAppendingString:self.guid];
    } else {
        return [kSqlitePathForTest stringByAppendingString:self.guid];
    }
}

- (NSString *)databaseFilenamePrefix {
    return @"test_command_history.sqlite";
}

- (NSTimeInterval)now {
    return self.currentTime ?: kDefaultTime;
}

- (BOOL)saveToDisk {
    return YES;
}

@end

@interface iTermShellHistoryControllerWithRAMStoreForTesting : iTermShellHistoryControllerForTesting
@end

@implementation iTermShellHistoryControllerWithRAMStoreForTesting

- (BOOL)shouldSaveToDisk {
    return NO;
}

@end

@interface iTermShellHistoryControllerWithConfigurableStoreDefaultingToDiskForTesting : iTermShellHistoryControllerForTesting
@property(nonatomic, retain) NSNumber *shouldSaveToDisk;
@end

@implementation iTermShellHistoryControllerWithConfigurableStoreDefaultingToDiskForTesting

- (BOOL)saveToDisk {
    return self.shouldSaveToDisk ? self.shouldSaveToDisk.boolValue : YES;
}

@end

@interface iTermShellHistoryTest : XCTestCase

@end

@implementation iTermShellHistoryTest {
    NSTimeInterval _now;
    NSString *_guid;
}

- (void)setUp {
    _guid = [NSString uuid];
    [[NSFileManager defaultManager] removeItemAtPath:[kSqlitePathForTest stringByAppendingString:_guid] error:nil];
}

#pragma mark - Command History

- (void)testSuccessfulCommandHistoryMigration {
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
    NSString *plistPath = [kFakeCommandHistoryPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:dictionary toFile:plistPath];

    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:plistPath isDirectory:nil]);
    iTermShellHistoryController *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:plistPath isDirectory:nil]);
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:[kSqlitePathForTest stringByAppendingString:_guid]
                                                   isDirectory:nil]);

    for (int iteration = 0; iteration < 2; iteration++) {
        if (iteration == 1) {
            // Re-create the history controller to verify that values can be loaded
            historyController = [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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

- (VT100RemoteHost *)addEntriesWithCommonPrefixes:(iTermShellHistoryControllerForTesting *)historyController {
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

- (void)testSearchCommandEntriesByPrefix {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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

- (void)testSearchCommandUsesByPrefix {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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

- (void)testHaveCommandsForHost {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
    
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];

    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
}

- (void)testEraseCommandHistoryForHost {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    
    // Add command for first host
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    
    // Add command for second host
    VT100RemoteHost *remoteHost2 = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost2.username = @"user2";
    remoteHost2.hostname = @"host2";
    [historyController addCommand:@"command"
                           onHost:remoteHost2
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    
    // Ensure both are present.
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost2]);
    
    // Erase first host.
    [historyController eraseCommandHistoryForHost:remoteHost];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
    
    // Make sure first host's data is gone but second host's remains.
    XCTAssertEqual([[historyController commandUsesForHost:remoteHost] count], 0);
    XCTAssert([historyController haveCommandsForHost:remoteHost2]);
    XCTAssertEqual([[historyController commandUsesForHost:remoteHost2] count], 1);

    // Create a new history controller and make sure the change persists.
    historyController = [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost2]);
}

- (void)testEraseCommandHistoryWhenSavingToDisk {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
    [historyController eraseCommandHistory:YES directories:NO];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
    XCTAssertEqual([[historyController commandUsesForHost:remoteHost] count], 0);
    
    historyController = [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
}

- (void)testEraseCommandHistoryInMemoryOnly {
    iTermShellHistoryControllerWithRAMStoreForTesting *historyController =
        [[[iTermShellHistoryControllerWithRAMStoreForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
    [historyController eraseCommandHistory:YES directories:NO];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
}

- (void)testFindCommandUseByMark {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
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
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory2"
                         withMark:mark];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory3"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    [historyController addCommand:@"command2"
                           onHost:remoteHost
                      inDirectory:@"/directory3"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    
    iTermCommandHistoryCommandUseMO *use = [historyController commandUseWithMarkGuid:mark.guid
                                                                              onHost:remoteHost];
    XCTAssertEqualObjects(use.directory, @"/directory2");
}

- (void)testGetAllCommandUsesForHost {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [self addEntriesWithCommonPrefixes:historyController];
    NSArray *uses;
    uses = [historyController commandUsesForHost:remoteHost];
    XCTAssertEqual(uses.count, self.commandWithCommonPrefixes.count);
}

- (void)testOldCommandUsesRemoved {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    
    // Just old enough to be removed
    historyController.currentTime = kDefaultTime - (60 * 60 * 24 * 90 + 1);
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    
    // Should stay
    historyController.currentTime = kDefaultTime;
    [historyController addCommand:@"command2"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    NSArray<iTermCommandHistoryEntryMO *> *entries =
        [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 2);

    historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    entries = [historyController commandHistoryEntriesWithPrefix:@"" onHost:remoteHost];
    XCTAssertEqual(entries.count, 1);
    XCTAssertEqualObjects([entries[0] command], @"command2");
}

#pragma mark - Generic

// There was a bug where migrating directories would stop on migrated commands. This tests migrating
// both to ensure this isn't an issue.
- (void)testCommandHistoryAndDirectoryMigration {
  _now = kDefaultTime;

  NSDictionary *commandDictionary =
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
                            ]
                    }
                ],
         };
    NSString *commandPlistPath = [kFakeCommandHistoryPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:commandDictionary toFile:commandPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);

    NSDictionary *directoryDictionary =
        @{
            @"user1@host1":
               @[
                   @{
                       @"path": @"/abc/def/ghi/good",
                       @"use count": @5,
                       @"last use": @(_now),
                       @"starred": @NO,
                    },
                ]
         };
    NSString *directoriesPlistPath = [kFakeDirectoriesPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:directoryDictionary toFile:directoriesPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    iTermShellHistoryController *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    NSArray<iTermCommandHistoryEntryMO *> *actualEntries =
        [historyController commandHistoryEntriesWithPrefix:@""
                                                    onHost:remoteHost];
    XCTAssertEqual(1, actualEntries.count);

    NSArray<iTermRecentDirectoryMO *> *actualDirectories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(1, actualDirectories.count);
}

// If you migrate from plist when there's already a Core Data database, it should just merge it
// in without causing duplicate host records.
- (void)testNoDuplicateHostRecordsAfterDoubleMigration {
  _now = kDefaultTime;

  NSDictionary *commandDictionary =
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
                            ]
                    }
                ],
         };
    NSString *commandPlistPath = [kFakeCommandHistoryPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:commandDictionary toFile:commandPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);

    NSDictionary *directoryDictionary =
        @{
            @"user1@host1":
               @[
                   @{
                       @"path": @"/abc/def/ghi/good1",
                       @"use count": @5,
                       @"last use": @(_now),
                       @"starred": @NO,
                    },
                ]
         };
    NSString *directoriesPlistPath = [kFakeDirectoriesPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:directoryDictionary toFile:directoriesPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    iTermShellHistoryController *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Second migration.
    NSDictionary *commandDictionary2 =
        @{
            @"user1@host1":
               @[
                   @{
                       @"command": @"command2",
                       @"uses": @10,
                       @"last used": @(_now),
                       @"use times":
                           @[
                               @[ @(_now),
                                  @"/path1",
                                  @"mark-guid-1",
                                  @"command1",
                                ],
                            ]
                    }
                ],
         };
    [NSKeyedArchiver archiveRootObject:commandDictionary2 toFile:commandPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);

    NSDictionary *directoryDictionary2 =
        @{
            @"user1@host1":
               @[
                   @{
                       @"path": @"/abc/def/ghi/good2",
                       @"use count": @5,
                       @"last use": @(_now),
                       @"starred": @NO,
                    },
                ]
         };
    [NSKeyedArchiver archiveRootObject:directoryDictionary2 toFile:directoriesPlistPath];
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:commandPlistPath isDirectory:nil]);
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:directoriesPlistPath isDirectory:nil]);

    ////////////////////////////////////////////////////////////////////////////////////////////////
    // Make sure things are sane.
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    NSArray<iTermCommandHistoryEntryMO *> *actualEntries =
        [historyController commandHistoryEntriesWithPrefix:@""
                                                    onHost:remoteHost];
    XCTAssertEqual(2, actualEntries.count);

    NSArray<iTermRecentDirectoryMO *> *actualDirectories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(2, actualDirectories.count);
}

- (void)testCorruptDatabase {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [self addEntriesWithCommonPrefixes:historyController];
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:[kSqlitePathForTest stringByAppendingString:_guid]];
    for (int i = 1024; i < data.length; i += 16) {
        ((char *)data.mutableBytes)[i] = i & 0xff;
    }
    [data writeToFile:[kSqlitePathForTest stringByAppendingString:_guid] atomically:NO];

    historyController = [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
}

- (void)testInMemoryStoreIsEvanescent {
    iTermShellHistoryControllerWithRAMStoreForTesting *historyController =
        [[[iTermShellHistoryControllerWithRAMStoreForTesting alloc] initWithGuid:_guid] autorelease];
    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    [historyController addCommand:@"command"
                           onHost:remoteHost
                      inDirectory:@"directory"
                         withMark:[[[VT100ScreenMark alloc] init] autorelease]];
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
    
    historyController =
        [[[iTermShellHistoryControllerWithRAMStoreForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssertFalse([historyController haveCommandsForHost:remoteHost]);
}

#pragma mark - Directories

- (void)testSuccessfulDirectoriesMigration {
    _now = kDefaultTime;
    NSDictionary *dictionary =
        @{
            @"user1@host1":
               @[
                   @{
                       @"path": @"/abc/def/ghi/good",
                       @"use count": @5,
                       @"last use": @(_now),
                       @"starred": @NO,
                    },
                   @{
                       @"path": @"/abc/def/ghi/old",
                       @"use count": @5,
                       @"last use": @(_now - 86400 * 365),
                       @"starred": @NO,
                    },
                   @{
                       @"path": @"/abc/def/ghi/old_but_starred",
                       @"use count": @5,
                       @"last use": @(_now - 86400 * 365),
                       @"starred": @YES,
                    },
                ],
            @"user2@host2":
                @[
                   @{
                       @"path": @"/abc/def/ghi/old",
                       @"use count": @5,
                       @"last use": @(_now - 86400 * 365),
                       @"starred": @NO,
                    },
                 ]
           };
    NSString *plistPath = [kFakeDirectoriesPlistPath stringByAppendingString:_guid];
    [NSKeyedArchiver archiveRootObject:dictionary toFile:plistPath];

    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:plistPath isDirectory:nil]);
    iTermShellHistoryController *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssert(![[NSFileManager defaultManager] fileExistsAtPath:plistPath isDirectory:nil]);
    XCTAssert([[NSFileManager defaultManager] fileExistsAtPath:[kSqlitePathForTest stringByAppendingString:_guid]
                                                   isDirectory:nil]);

    for (int iteration = 0; iteration < 2; iteration++) {
        if (iteration == 1) {
            // Re-create the history controller to verify that values can be loaded
            historyController = [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
        }
        iTermRecentDirectoryMO *directory;

        VT100RemoteHost *host = [[[VT100RemoteHost alloc] init] autorelease];
        host.username = @"user1";
        host.hostname = @"host1";
        NSArray<iTermRecentDirectoryMO *> *directories = [historyController directoriesSortedByScoreOnHost:host];

        XCTAssertEqual(2, directories.count);

        directory = directories[0];
        XCTAssertEqualObjects(@"/abc/def/ghi/old_but_starred", directory.path);
        XCTAssertEqualObjects(@5, directory.useCount);
        XCTAssertEqualObjects(@(_now - 86400 * 365), directory.lastUse);
        XCTAssertEqualObjects(@YES, directory.starred);

        directory = directories[1];
        XCTAssertEqualObjects(@"/abc/def/ghi/good", directory.path);
        XCTAssertEqualObjects(@5, directory.useCount);
        XCTAssertEqualObjects(@(_now), directory.lastUse);
        XCTAssertEqualObjects(@NO, directory.starred);

        // Host 2 (had only one directory that should be removed for old age).
        host.username = @"user2";
        host.hostname = @"host2";
        directories = [historyController directoriesSortedByScoreOnHost:host];

        XCTAssertEqual(0, directories.count);
    }
}

- (void)testAddFirstDirectoryToNewHost {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    const NSTimeInterval now = 1000000;
    historyController.currentTime = now;

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray<iTermRecentDirectoryMO *> *directories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 0);

    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];
    directories = [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 1);
    
    iTermRecentDirectoryMO *directory = directories[0];
    XCTAssertEqualObjects(directory.path, @"/test/path");
    XCTAssertEqualObjects(directory.useCount, @1);
    XCTAssertEqualObjects(directory.lastUse, @(now));
    XCTAssertEqual(directory.starred.boolValue, NO);
    XCTAssertEqualObjects(directory.remoteHost.hostname, remoteHost.hostname);
    XCTAssertEqualObjects(directory.remoteHost.username, remoteHost.username);
}

- (void)testReuseDirectory {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    NSArray<iTermRecentDirectoryMO *> *directories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 0);

    historyController.currentTime = 500;
    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];

    NSTimeInterval now = 1000;
    historyController.currentTime = now;
    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];

    directories = [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 1);
    
    iTermRecentDirectoryMO *directory = directories[0];
    XCTAssertEqualObjects(directory.path, @"/test/path");
    XCTAssertEqualObjects(directory.useCount, @2);
    XCTAssertEqualObjects(directory.lastUse, @(now));
    XCTAssertEqual(directory.starred.boolValue, NO);
    XCTAssertEqualObjects(directory.remoteHost.hostname, remoteHost.hostname);
    XCTAssertEqualObjects(directory.remoteHost.username, remoteHost.username);
}

- (void)testSetDirectoryStarred {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    
    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];

    NSArray<iTermRecentDirectoryMO *> *directories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 1);

    // Star it
    iTermRecentDirectoryMO *directory = directories[0];
    [historyController setDirectory:directory starred:YES];

    directories = [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 1);
    directory = directories[0];

    XCTAssertEqualObjects(directory.starred, @YES);

    // Un-star it
    [historyController setDirectory:directory starred:NO];

    directories = [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 1);
    directory = directories[0];

    XCTAssertEqualObjects(directory.starred, @NO);

}

- (void)testAbbreviationSafeIndexes {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";

    NSArray *paths = @[ @"/a1/b1/c1/d1/e1/f1",
                        @"/a1/b1/c2/d1/e1/f1",  // Can't abbreviate c1/c2
                        @"/a1/b1/c1/d1/e2" ];  // Can't abbreviate e1/e2

    for (NSString *path in paths) {
        [historyController recordUseOfPath:path onHost:remoteHost isChange:YES];
    }

    NSArray<iTermRecentDirectoryMO *> *directories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(directories.count, 3);

    for (NSInteger i = 0; i < directories.count; i++) {
        iTermRecentDirectoryMO *directory = directories[i];
        if ([directory.path isEqualToString:paths[0]]) {

            NSIndexSet *actual = [historyController abbreviationSafeIndexesInRecentDirectory:directory];
            NSMutableIndexSet *expected = [NSMutableIndexSet indexSet];
            [expected addIndex:0];
            [expected addIndex:1];
            [expected addIndex:3];
            [expected addIndex:5];

            XCTAssertEqualObjects(actual, expected);
            break;
        }
    }
}

- (void)testSortDirectoriesByScore {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";

    // Directories sort by: starred, int(log2(useCount)), lastUseDate.

    for (NSNumber *starred in @[ @YES, @NO ]) {
        for (NSNumber *useCount in @[ @1, @8, @16 ]) {
            for (NSNumber *date in @[ @1, @2 ]) {
                historyController.currentTime = date.doubleValue;
                for (int i = 0; i < useCount.intValue; i++) {
                    NSString *path = [NSString stringWithFormat:@"/%@/uses%@/date%@",
                                         starred.boolValue ? @"starred" : @"unstarred",
                                         useCount,
                                         date];
                    iTermRecentDirectoryMO *directory =
                        [historyController recordUseOfPath:path onHost:remoteHost isChange:YES];
                    if (starred.boolValue && i == 0) {
                        [historyController setDirectory:directory starred:YES];
                    }
                }
            }
        }
    }

    // Number of uses will be considered equivalent for these so they'll sort by date.
    historyController.currentTime = 2;
    for (int i = 0; i < 9; i++) {
        [historyController recordUseOfPath:@"/unstarred/uses9/date2" onHost:remoteHost isChange:YES];
    }
    historyController.currentTime = 1;
    for (int i = 0; i < 10; i++) {
        [historyController recordUseOfPath:@"/unstarred/uses10/date1" onHost:remoteHost isChange:YES];
    }

    // unstarred, rarely used, old
    NSArray *expected = @[ @"/starred/uses16/date2",
                           @"/starred/uses16/date1",
                           @"/starred/uses8/date2",
                           @"/starred/uses8/date1",
                           @"/starred/uses1/date2",
                           @"/starred/uses1/date1",
                           @"/unstarred/uses16/date2",
                           @"/unstarred/uses16/date1",
                           @"/unstarred/uses9/date2",
                           @"/unstarred/uses8/date2",
                           @"/unstarred/uses10/date1",
                           @"/unstarred/uses8/date1",
                           @"/unstarred/uses1/date2",
                           @"/unstarred/uses1/date1" ];
    NSArray<iTermRecentDirectoryMO *> *directories =
        [historyController directoriesSortedByScoreOnHost:remoteHost];
    XCTAssertEqual(expected.count, directories.count);

    for (int i = 0; i < directories.count; i++) {
        XCTAssertEqualObjects(expected[i], [directories[i] path]);
    }
}

- (void)testHaveDirectoriesOnHost {
    iTermShellHistoryControllerForTesting *historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";

    XCTAssertFalse([historyController haveDirectoriesForHost:remoteHost]);
    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);

    historyController =
        [[[iTermShellHistoryControllerForTesting alloc] initWithGuid:_guid] autorelease];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
}

- (void)testBackingStoreDidChange {
    iTermShellHistoryControllerWithConfigurableStoreDefaultingToDiskForTesting *historyController =
        [[[iTermShellHistoryControllerWithConfigurableStoreDefaultingToDiskForTesting alloc] initWithGuid:_guid] autorelease];

    VT100RemoteHost *remoteHost = [[[VT100RemoteHost alloc] init] autorelease];
    remoteHost.username = @"user1";
    remoteHost.hostname = @"host1";
    VT100ScreenMark *mark = [[[VT100ScreenMark alloc] init] autorelease];

    [historyController recordUseOfPath:@"/test/path" onHost:remoteHost isChange:YES];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory1"
                         withMark:mark];

    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);

    // Initial value is saved to disk. Flip it to RAM. Should lose no data.
    historyController.shouldSaveToDisk = @NO;
    [historyController backingStoreTypeDidChange];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);

    [historyController recordUseOfPath:@"/test2/path2" onHost:remoteHost isChange:YES];
    [historyController addCommand:@"command1"
                           onHost:remoteHost
                      inDirectory:@"/directory1"
                         withMark:mark];

    // Back to disk. Should lose no data.
    historyController.shouldSaveToDisk = @YES;
    [historyController backingStoreTypeDidChange];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);

    // Back to RAM.
    historyController.shouldSaveToDisk = @NO;
    [historyController backingStoreTypeDidChange];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);

    // Back to disk.
    historyController.shouldSaveToDisk = @YES;
    [historyController backingStoreTypeDidChange];
    XCTAssertTrue([historyController haveDirectoriesForHost:remoteHost]);
    XCTAssertTrue([historyController haveCommandsForHost:remoteHost]);
}

@end
