//
//  iTermToolbeltTest.m
//  iTerm2
//
//  Created by George Nachman on 7/4/15.
//
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "CommandHistory.h"
#import "iTermController.h"
#import "iTermRootTerminalView.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "Trigger.h"
#import "VT100RemoteHost.h"

@interface iTermToolbeltTest : XCTestCase

@end

@implementation iTermToolbeltTest {
    PseudoTerminal *_windowController;  // weak
    PTYSession *_session;  // weak
    iTermRootTerminalView *_view;  // weak
}

- (void)setUp {
    [super setUp];

    // Erase command history for the remotehost we test with.
    VT100RemoteHost *host = [[[VT100RemoteHost alloc] init] autorelease];
    host.hostname = @"hostname";
    host.username = @"user";
    [[CommandHistory sharedInstance] eraseHistoryForHost:host];

    // Create a window and save convenience pointers to its various bits.
    _session = [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil];
    _windowController = (PseudoTerminal *)_session.tab.realParentWindow;
    _view = (iTermRootTerminalView *)_windowController.window.contentView;

    // Make it big so all the tools fit.
    [_windowController.window setFrame:_windowController.window.screen.visibleFrame display:YES];

    // Show the toolbelt
    if (!_view.shouldShowToolbelt) {
        [_windowController toggleToolbeltVisibility:self];
    }

    // Show all the tools
    for (NSString *toolName in [ToolbeltView allTools]) {
        if (![ToolbeltView shouldShowTool:toolName]) {
            [ToolbeltView toggleShouldShowTool:toolName];
        }
    }

    // Define a capture output trigger.
    NSDictionary *trigger = @{ kTriggerRegexKey: @"error:",
                               kTriggerActionKey: @"CaptureTrigger",
                               kTriggerParameterKey: @"sleep 99999" };

    [_session setSessionSpecificProfileValues:@{ KEY_TRIGGERS: @[ trigger ] }];
}

- (void)tearDown {
    [[_windowController retain] autorelease];
    [_session terminate];
    [_windowController close];

    [super tearDown];
}

#pragma mark - Utilities

- (void)sendData:(NSData *)data toTerminal:(VT100Terminal *)terminal {
    [terminal.parser putStreamData:data.bytes length:data.length];
    CVector vector;
    CVectorCreate(&vector, 1);
    [terminal.parser addParsedTokensToVector:&vector];
    for (int i = 0; i < CVectorCount(&vector); i++) {
        [terminal executeToken:CVectorGetObject(&vector, i)];
    }
    CVectorDestroy(&vector);
}

- (void)sendPromptAndStartCommand:(NSString *)command toSession:(PTYSession *)session {
    NSString *promptLine = [NSString stringWithFormat:
                            @"%c]1337;RemoteHost=user@hostname%c"
                            @"%c]1337;CurrentDir=/dir%c"
                            @"%c]133;A%c"
                            @"> "
                            @"%c]133;B%c"
                            @"%@"
                            @"%c]133;C%c",
                            VT100CC_ESC, VT100CC_BEL,  // RemoteHost
                            VT100CC_ESC, VT100CC_BEL,  // CurrentDir
                            VT100CC_ESC, VT100CC_BEL,  // FinalTerm A
                            VT100CC_ESC, VT100CC_BEL,  // FinalTerm B
                            command,
                            VT100CC_ESC, VT100CC_BEL];  // FinalTerm C
    [self sendData:[promptLine dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:session.terminal];
}

- (void)endCommand {
    NSString *promptLine = [NSString stringWithFormat:@"%c]133;D;1%c",
                            VT100CC_ESC, VT100CC_BEL];
    [self sendData:[promptLine dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
}

- (void)writeLongCommandOutput {
    for (int i = 0; i < _session.screen.height * 2; i++) {
        [self sendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]
            toTerminal:_session.terminal];
    }
}

#pragma mark - Tests

- (void)testToolbeltIsVisible {
    // Ensure the toolbelt is visible.
    XCTAssert(_view.shouldShowToolbelt);
    XCTAssert(_view.toolbelt);
    XCTAssert(_view.toolbelt.window);
}

#pragma mark Captured Output

- (void)testToolbeltHasCapturedOutputTool {
    ToolCapturedOutputView *tool = (ToolCapturedOutputView *)[_view.toolbelt
                                                              toolWithName:kCapturedOutputToolName];
    XCTAssert(tool);
}

- (void)testCapturedOutputUpdatesOnMatch {
    ToolCapturedOutputView *tool = (ToolCapturedOutputView *)[_view.toolbelt
                                                              toolWithName:kCapturedOutputToolName];
    XCTAssertEqual(tool.tableView.numberOfRows, 0);
    // Gotta have a command mark for captured output to work
    [self sendPromptAndStartCommand:@"make" toSession:_session];
    [self sendData:[@"Hello\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    XCTAssertEqual(tool.tableView.numberOfRows, 0);
    [self sendData:[@"error: blah\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    XCTAssertEqual(tool.tableView.numberOfRows, 1);
}

- (void)testCapturedOutputShowsLineOnClick {
    ToolCapturedOutputView *tool = (ToolCapturedOutputView *)[_view.toolbelt
                                                              toolWithName:kCapturedOutputToolName];
    XCTAssertEqual(tool.tableView.numberOfRows, 0);
    // Gotta have a command mark for captured output to work
    [self sendPromptAndStartCommand:@"make" toSession:_session];
    NSRect rectForFirstCellOfCapturedLine = _session.textview.cursorFrame;
    [self sendData:[@"error: blah\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    [self writeLongCommandOutput];
    // Update scroll position for new text
    [_session.textview refresh];
    XCTAssert(!NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                                rectForFirstCellOfCapturedLine));

    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    XCTAssert(NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                               rectForFirstCellOfCapturedLine));
}

- (void)testCapturedOutputActivatesTriggerOnDoubleClick {
    ToolCapturedOutputView *tool = (ToolCapturedOutputView *)[_view.toolbelt
                                                              toolWithName:kCapturedOutputToolName];
    XCTAssertEqual(tool.tableView.numberOfRows, 0);
    // Gotta have a command mark for captured output to work
    [self sendPromptAndStartCommand:@"make" toSession:_session];
    [self sendData:[@"error: blah\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];

    // Select the row
    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    XCTAssert(!_session.hasCoprocess);

    // Fake a double click on it
    [tool.tableView.delegate performSelector:tool.tableView.doubleAction withObject:nil];

    XCTAssert(_session.hasCoprocess);
}

#pragma mark Command History

- (void)testCommandHistoryBoldsCommandsForCurrentSession {
    PTYSession *otherSession = [[iTermController sharedInstance] launchBookmark:nil
                                                                     inTerminal:_windowController];

    // Set the hostname for both sessions
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self sendPromptAndStartCommand:@"command 2" toSession:otherSession];

    // Send the first command to tab 0
    [self sendData:[@"Output 1" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    [self endCommand];

    // Send the second command to tab 1
    [self sendData:[@"Output 2" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    [self endCommand];

    ToolCommandHistoryView *tool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];

    // Select tab 0 and get its two commands from the table view.
    [_windowController.tabView selectTabViewItemAtIndex:0];
    NSArray *values = @[ [tool.tableView.dataSource tableView:tool.tableView
                                    objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                          row:0],
                         [tool.tableView.dataSource tableView:tool.tableView
                                    objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                          row:1] ];

    // First one should be bold.
    XCTAssert([values[0] isKindOfClass:[NSAttributedString class]]);
    XCTAssert([values[1] isKindOfClass:[NSString class]]);

    // Select tab 1 and get its two commands from the table view.
    [_windowController.tabView selectTabViewItemAtIndex:1];
    values = @[ [tool.tableView.dataSource tableView:tool.tableView
                           objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                 row:0],
                [tool.tableView.dataSource tableView:tool.tableView
                           objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                 row:1] ];

    // Second one should be bold.
    XCTAssert([values[0] isKindOfClass:[NSString class]]);
    XCTAssert([values[1] isKindOfClass:[NSAttributedString class]]);
}

- (void)testCommandHistoryScrollsToClickedCommand {
    NSRect firstCommandRect = _session.textview.enclosingScrollView.documentVisibleRect;
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self writeLongCommandOutput];
    [self endCommand];

    [self sendPromptAndStartCommand:@"command 2" toSession:_session];
    [self writeLongCommandOutput];
    [self endCommand];

    ToolCommandHistoryView *tool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];

    XCTAssert(!NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                                firstCommandRect));

    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    XCTAssert(NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                               firstCommandRect));

}

- (void)testCommandHistoryUpdatesWhenNewCommandIsEntered {
    ToolCommandHistoryView *tool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];

    // Send a prompt first so we know the hostname.
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self writeLongCommandOutput];
    [self endCommand];

    int n = tool.tableView.numberOfRows;

    [self sendPromptAndStartCommand:@"command 2" toSession:_session];
    [self writeLongCommandOutput];
    [self endCommand];

    XCTAssertEqual(tool.tableView.numberOfRows, n + 1);
}

- (void)testCommandHistoryEntersCommandOnDoubleClick {
}

- (void)testCommandHistoryLinkedToCapturedOutput {
}

- (void)testDirectoriesUpdatesOnCd {
}

- (void)testDirectoriesEntersCommandOnDoubleClick {
}

- (void)testJobsUpdatesFromTimer {
}

- (void)testToolbeltImpingesOnWindowWhenNearRightEdge {
}

- (void)testToolbeltGrowsWhenSpaceIsAvailableOnRight {
}


@end
