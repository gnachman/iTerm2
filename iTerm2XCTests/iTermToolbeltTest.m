//
//  iTermToolbeltTest.m
//  iTerm2
//
//  Created by George Nachman on 7/4/15.
//
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "iTermController.h"
#import "iTermRootTerminalView.h"
#import "ToolCapturedOutputView.h"
#import "Trigger.h"

@interface iTermToolbeltTest : XCTestCase

@end

@implementation iTermToolbeltTest {
    PseudoTerminal *_windowController;  // weak
    PTYSession *_session;  // weak
    iTermRootTerminalView *_view;  // weak
}

- (void)setUp {
    [super setUp];
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
                               kTriggerParameterKey: @"echo hello" };

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

- (void)sendPrompt {
    NSString *promptLine = [NSString stringWithFormat:@"%c]133;A%c> %c]133;B%cmake%c]133;C%c",
                            VT100CC_ESC, VT100CC_BEL,
                            VT100CC_ESC, VT100CC_BEL,
                            VT100CC_ESC, VT100CC_BEL];
    [self sendData:[promptLine dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
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
    [self sendPrompt];
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
    [self sendPrompt];
    NSRect rectForFirstCellOfCapturedLine = _session.textview.cursorFrame;
    [self sendData:[@"error: blah\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    for (int i = 0; i < _session.screen.height * 2; i++) {
        [self sendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]
            toTerminal:_session.terminal];
    }
    // Update scroll position for new text
    [_session.textview refresh];
    XCTAssert(!NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                                rectForFirstCellOfCapturedLine));

    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    XCTAssert(NSIntersectsRect(_session.textview.enclosingScrollView.documentVisibleRect,
                               rectForFirstCellOfCapturedLine));
}

- (void)testCapturedOutputActivatesTriggerOnDoubleClick {
}

- (void)testCommandHistoryBoldsCommandsForCurrentSession {
}

- (void)testCommandHistoryScrollsToClickedCommand {
}

- (void)testCommandHistoryUpdatesWhenNewCommandIsEntered {
}

- (void)testCommandHistoryEntersCommandOnDoubleClick {
}

- (void)testDirectoriesUpdatesOnCd {
}

- (void)testDirectoriesEntersCommandOnDoubleClick {
}

- (void)testJobsUpdatesFromTimer {
}

@end
