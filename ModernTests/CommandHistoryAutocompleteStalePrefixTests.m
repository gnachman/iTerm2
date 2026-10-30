//
//  CommandHistoryAutocompleteStalePrefixTests.m
//  ModernTests
//
//  Issue 13168: choosing an entry from the auto command history popup turned
//  “aws” into “awss sso login …”. The popup inserts the chosen command minus
//  the number of characters that were typed when it last loaded. PTYSession
//  only reloads it while the cell under the cursor is empty, and a zsh
//  autosuggestion drawn after the cursor fills that cell, so the popup keeps
//  the length from before the last keystroke and inserts one character too
//  many.
//
//  These use a real PTYSession as the popup's delegate and draw the prompt,
//  the typed text, and the autosuggestion through the real parser.
//

#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "CommandHistoryPopup.h"
#import "PTYSession.h"
#import "ProfileModel.h"
#import "VT100Screen.h"
#import "VT100Parser.h"
#import "VT100ScreenMutableState.h"
#import "VT100Terminal.h"
#import "WindowControllerInterface.h"

// Swift class ModernTests cannot see through iTerm2SharedARC-Swift.h.
@interface iTermHeadlessWindowController : NSObject<WindowControllerInterface>
- (instancetype)initWithFrame:(NSRect)frame;
@end

@interface CommandHistoryPopupWindowController (Testing)
- (NSString *)insertableString;
@end

// Stands in for iTermCommandHistoryEntryMO, which the popup reads through
// -command and -timeOfLastUse only. Avoids standing up a Core Data store.
@interface CommandHistoryStalePrefixEntryStandIn : NSObject
@property(nonatomic, copy) NSString *command;
@property(nonatomic, strong) NSNumber *timeOfLastUse;
@end

@implementation CommandHistoryStalePrefixEntryStandIn
@end

static NSString *const kHistoricalCommand = @"aws sso login --profile=athena-dev";

@interface CommandHistoryAutocompleteStalePrefixTests : XCTestCase
@end

@implementation CommandHistoryAutocompleteStalePrefixTests {
    PTYSession *_session;
    iTermHeadlessWindowController *_parent;
    CommandHistoryPopupWindowController *_popup;
}

- (void)setUp {
    [super setUp];
    Profile *profile = [[ProfileModel sharedInstance] defaultBookmark];
    XCTAssertNotNil(profile);
    _session = [[PTYSession alloc] initSynthetic:YES];
    _session.profile = profile;
    const NSSize frameSize = NSMakeSize(800, 400);
    _parent = [[iTermHeadlessWindowController alloc] initWithFrame:NSMakeRect(0, 0, frameSize.width, frameSize.height)];
    [_session setScreenSize:frameSize parent:_parent];
    [_session setPreferencesFromAddressBookEntry:profile];
    [_session setSize:VT100GridSizeMake(80, 25)];
    // No process is attached, so turn the terminal on as the session would on launch.
    [_session.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                     VT100ScreenMutableState *mutableState,
                                                     id<VT100ScreenDelegate> delegate) {
        mutableState.terminalEnabled = YES;
        terminal.termType = @"xterm";
    }];
    _popup = [[CommandHistoryPopupWindowController alloc] initForAutoComplete:YES];
    _popup.delegate = _session;
}

- (void)tearDown {
    _popup.delegate = nil;
    [_popup shutdown];
    _popup = nil;
    _session = nil;
    _parent = nil;
    [super tearDown];
}

#pragma mark - Tests

// Baseline: when the popup loaded with exactly what is typed, it inserts the
// rest of the command.
- (void)testInsertsRemainderWhenPopupIsCurrent {
    [self feed:[[self prompt] stringByAppendingString:@"aw"]];
    [self loadPopup];

    XCTAssertEqualObjects(_session.currentCommandUpToCursor, @"aw");
    XCTAssertEqualObjects([_popup insertableString], @"s sso login --profile=athena-dev");
}

// The user types “aw” (the popup loads), then “s”. zsh-autosuggestions draws
// the rest of the suggested command in gray after the cursor, so the session
// doesn't reload the popup. Choosing the entry must still produce the
// historical command, not “awss sso login …”.
- (void)testAutosuggestionAfterCursorDoesNotDoubleLastTypedCharacter {
    [self feed:[[self prompt] stringByAppendingString:@"aw"]];
    [self loadPopup];

    [self feed:[@"s" stringByAppendingString:[self autosuggestion:@" sso login --profile=athena-dev"]]];

    // Precondition that describes the reported state.
    XCTAssertFalse(_session.eligibleForAutoCommandHistory,
                   @"The suggestion fills the cell under the cursor, so the session doesn't reload the popup");

    NSString *result = [@"aws" stringByAppendingString:[_popup insertableString] ?: @""];
    XCTAssertEqualObjects(result, kHistoricalCommand);
}

// The same staleness without autosuggestions: the user types “s” and chooses
// the entry before the popup reloads. Choosing must not depend on the reload
// having happened.
- (void)testTypingAfterLoadWithoutReloadDoesNotDoubleLastTypedCharacter {
    [self feed:[[self prompt] stringByAppendingString:@"aw"]];
    [self loadPopup];

    [self feed:@"s"];

    XCTAssertEqualObjects(_session.currentCommandUpToCursor, @"aws");
    NSString *result = [@"aws" stringByAppendingString:[_popup insertableString] ?: @""];
    XCTAssertEqualObjects(result, kHistoricalCommand);
}

// The user types a character that no longer matches the entry before the
// popup reloads. Inserting any suffix of the entry would be wrong.
- (void)testTypedTextThatNoLongerMatchesInsertsNothing {
    [self feed:[[self prompt] stringByAppendingString:@"aw"]];
    [self loadPopup];

    [self feed:@"x"];

    XCTAssertNil([_popup insertableString]);
}

// History matches prefixes case-insensitively, so “AW” lists “aws sso login …”.
// Choosing it must insert the rest of the command after the typed text.
- (void)testTypedTextInDifferentCaseInsertsRemainder {
    [self feed:[[self prompt] stringByAppendingString:@"AW"]];
    [self loadPopup];

    XCTAssertEqualObjects([_popup insertableString], @"s sso login --profile=athena-dev");
}

// Same, after the popup went stale.
- (void)testTypedTextInDifferentCaseAfterStaleLoadInsertsRemainder {
    [self feed:[[self prompt] stringByAppendingString:@"aw"]];
    [self loadPopup];

    [self feed:@"S"];

    XCTAssertEqualObjects([_popup insertableString], @" sso login --profile=athena-dev");
}

#pragma mark - Helpers

- (void)sync {
    [_session.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                     VT100ScreenMutableState *mutableState,
                                                     id<VT100ScreenDelegate> delegate) {
    }];
}

- (void)feed:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    [_session.screen performBlockWithJoinedThreads:^(VT100Terminal *terminal,
                                                     VT100ScreenMutableState *mutableState,
                                                     id<VT100ScreenDelegate> delegate) {
        VT100Parser *parser = [[VT100Parser alloc] init];
        parser.encoding = NSUTF8StringEncoding;
        [parser putStreamData:data.bytes length:(int)data.length];
        CVector vector;
        CVectorCreate(&vector, 100);
        [parser addParsedTokensToVector:&vector];
        for (int i = 0; i < CVectorCount(&vector); i++) {
            [terminal executeToken:CVectorGetObject(&vector, i)];
        }
        CVectorDestroy(&vector);
    }];
    [self sync];
}

- (NSString *)osc133:(NSString *)body {
    return [NSString stringWithFormat:@"\e]133;%@\a", body];
}

// A zsh prompt as iTerm2's shell integration brackets it.
- (NSString *)prompt {
    return [NSString stringWithFormat:@"%@%% %@", [self osc133:@"A"], [self osc133:@"B"]];
}

// zsh-autosuggestions draws the suggestion dimmed after the cursor and moves
// the cursor back to the end of what was typed.
- (NSString *)autosuggestion:(NSString *)suffix {
    return [NSString stringWithFormat:@"\e[90m%@\e[0m\e[%@D", suffix, @(suffix.length)];
}

// What the session does when the popup opens or the command changes and the
// session is eligible: load entries matching what is typed.
- (void)loadPopup {
    CommandHistoryStalePrefixEntryStandIn *entry = [[CommandHistoryStalePrefixEntryStandIn alloc] init];
    entry.command = kHistoricalCommand;
    entry.timeOfLastUse = @0;
    [_popup loadCommands:@[ entry ]
          partialCommand:_session.currentCommand ?: @""
     sortChronologically:NO];
}

@end
