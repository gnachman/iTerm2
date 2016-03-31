//
//  iTermToolbeltTest.m
//  iTerm2
//
//  Created by George Nachman on 7/4/15.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermApplication.h"
#import "iTermController.h"
#import "iTermRootTerminalView.h"
#import "iTermShellHistoryController.h"
#import "PseudoTerminal.h"
#import "PTYTab.h"
#import "ToolCapturedOutputView.h"
#import "ToolCommandHistoryView.h"
#import "ToolDirectoriesView.h"
#import "Trigger.h"
#import "VT100RemoteHost.h"
#import <XCTest/XCTest.h>

@interface iTermToolbeltTest : XCTestCase<iTermToolbeltViewDelegate>
@property(nonatomic, retain) NSString *currentDir;
@end

@implementation iTermToolbeltTest {
    PseudoTerminal *_windowController;  // weak
    PTYSession *_session;  // weak
    iTermRootTerminalView *_view;  // weak

    NSMutableString *_insertedText;
    NSString *_currentDir;
}

- (void)setUp {
    [super setUp];

    _insertedText = [[NSMutableString alloc] init];
    _currentDir = [@"/dir" retain];

    // Erase command history for the remotehost we test with.
    VT100RemoteHost *host = [[[VT100RemoteHost alloc] init] autorelease];
    host.hostname = @"hostname";
    host.username = @"user";
    [[iTermShellHistoryController sharedInstance] eraseCommandHistoryForHost:host];

    // Erase directory history for the remotehost we test with.
    [[iTermShellHistoryController sharedInstance] eraseDirectoriesForHost:host];

    // Create a window and save convenience pointers to its various bits.
    _session = [[iTermController sharedInstance] launchBookmark:nil inTerminal:nil];
    _windowController = (PseudoTerminal *)_session.delegate.realParentWindow;
    _view = (iTermRootTerminalView *)_windowController.window.contentView;

    // Make it big so all the tools fit.
    [_windowController.window setFrame:_windowController.window.screen.visibleFrame display:YES];

    // Show the toolbelt
    if (!_view.shouldShowToolbelt) {
        [_windowController toggleToolbeltVisibility:self];
    }

    // Show all the tools
    for (NSString *toolName in [iTermToolbeltView allTools]) {
        if (![iTermToolbeltView shouldShowTool:toolName]) {
            [iTermToolbeltView toggleShouldShowTool:toolName];
        }
    }

    // Define a capture output trigger.
    NSDictionary *trigger = @{ kTriggerRegexKey: @"error:",
                               kTriggerActionKey: @"CaptureTrigger",
                               kTriggerParameterKey: @"sleep 99999" };

    [_session setSessionSpecificProfileValues:@{ KEY_TRIGGERS: @[ trigger ] }];
}

- (void)tearDown {
    iTermApplication *app = iTermApplication.sharedApplication;
    app.fakeCurrentEvent = nil;
    [_currentDir release];
    [_insertedText release];
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
    NSString *promptLine = [NSString stringWithFormat:
                            @"%c]1337;RemoteHost=user@hostname%c"
                            @"%c]1337;CurrentDir=%@%c"
                            @"%c]133;A%c"
                            @"> "
                            @"%c]133;B%c",
                            VT100CC_ESC, VT100CC_BEL,  // RemoteHost
                            VT100CC_ESC, _currentDir, VT100CC_BEL,  // CurrentDir
                            VT100CC_ESC, VT100CC_BEL,  // FinalTerm A
                            VT100CC_ESC, VT100CC_BEL];  // FinalTerm B
    [self sendData:[promptLine dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
}

- (void)sendPromptAndStartCommand:(NSString *)command toSession:(PTYSession *)session {
    NSString *promptLine = [NSString stringWithFormat:
                            @"%c]1337;RemoteHost=user@hostname%c"
                            @"%c]1337;CurrentDir=%@%c"
                            @"%c]133;A%c"
                            @"> "
                            @"%c]133;B%c"
                            @"%@"
                            @"%c]133;C%c",
                            VT100CC_ESC, VT100CC_BEL,  // RemoteHost
                            VT100CC_ESC, _currentDir, VT100CC_BEL,  // CurrentDir
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

#pragma mark - General Testse

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

    // TODO(georgen): Test that the first one should be bold.
    XCTAssert([values[0] isKindOfClass:[NSAttributedString class]]);
    XCTAssert([values[1] isKindOfClass:[NSAttributedString class]]);

    // Select tab 1 and get its two commands from the table view.
    [_windowController.tabView selectTabViewItemAtIndex:1];
    values = @[ [tool.tableView.dataSource tableView:tool.tableView
                           objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                 row:0],
                [tool.tableView.dataSource tableView:tool.tableView
                           objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                 row:1] ];

    // TODO(georgen): Test that the second one should be bold.
    XCTAssert([values[0] isKindOfClass:[NSAttributedString class]]);
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
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self endCommand];

    [self sendPrompt];

    ToolCommandHistoryView *tool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];
    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:tool.tableView.numberOfRows - 1]
                byExtendingSelection:NO];

    tool.toolWrapper.delegate.delegate = self;
    [tool.tableView.delegate performSelector:tool.tableView.doubleAction withObject:tool.tableView];
    XCTAssertEqualObjects(_insertedText, @"command 1");
}

- (void)testCommandHistoryWritesCdOnOptionDoubleClick {
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self endCommand];

    [self sendPrompt];

    ToolCommandHistoryView *tool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];
    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:tool.tableView.numberOfRows - 1]
                byExtendingSelection:NO];

    tool.toolWrapper.delegate.delegate = self;
    iTermApplication *app = iTermApplication.sharedApplication;
    CGEventRef fakeEvent = CGEventCreateKeyboardEvent(NULL, 0, true);
    CGEventSetFlags(fakeEvent, kCGEventFlagMaskAlternate);
    app.fakeCurrentEvent = [NSEvent eventWithCGEvent:fakeEvent];
    CFRelease(fakeEvent);

    [tool.tableView.delegate performSelector:tool.tableView.doubleAction withObject:tool.tableView.target];
    XCTAssertEqualObjects(_insertedText, [@"cd " stringByAppendingString:_currentDir]);
}

- (void)testCommandHistoryLinkedToCapturedOutput {
    [self sendPromptAndStartCommand:@"command 1" toSession:_session];
    [self sendData:[@"error: 1\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    [self endCommand];

    [self sendPromptAndStartCommand:@"command 2" toSession:_session];
    [self sendData:[@"error: 2\r\n" dataUsingEncoding:NSUTF8StringEncoding]
        toTerminal:_session.terminal];
    [self endCommand];

    ToolCapturedOutputView *capturedOutputTool =
        (ToolCapturedOutputView *)[_view.toolbelt toolWithName:kCapturedOutputToolName];
    ToolCommandHistoryView *commandHistoryTool =
        (ToolCommandHistoryView *)[_view.toolbelt toolWithName:kCommandHistoryToolName];

    // Select first command
    [commandHistoryTool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                              byExtendingSelection:NO];
    NSString *object;
    object = [capturedOutputTool.tableView.dataSource tableView:capturedOutputTool.tableView
                                      objectValueForTableColumn:capturedOutputTool.tableView.tableColumns[0]
                                                            row:0];
    XCTAssert([object containsString:@"error: 1"]);

    // Select second command
    [commandHistoryTool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:1]
                              byExtendingSelection:NO];

    object = [capturedOutputTool.tableView.dataSource tableView:capturedOutputTool.tableView
                                      objectValueForTableColumn:capturedOutputTool.tableView.tableColumns[0]
                                                            row:0];
    XCTAssert([object containsString:@"error: 2"]);

    // Select nothing
    [commandHistoryTool.tableView selectRowIndexes:[NSIndexSet indexSet]
                              byExtendingSelection:NO];
    object = [capturedOutputTool.tableView.dataSource tableView:capturedOutputTool.tableView
                                      objectValueForTableColumn:capturedOutputTool.tableView.tableColumns[0]
                                                            row:0];
    XCTAssert([object containsString:@"error: 2"]);
}

#pragma mark Directories

- (void)testDirectoriesUpdatesOnCd {
    [self sendPromptAndStartCommand:@"cd /tmp" toSession:_session];
    self.currentDir = @"/tmp";
    [self endCommand];
    [self sendPrompt];

    ToolDirectoriesView *tool =
        (ToolDirectoriesView *)[_view.toolbelt toolWithName:kRecentDirectoriesToolName];
    XCTAssertEqual(tool.tableView.numberOfRows, 2);

    NSAttributedString *object = [tool.tableView.dataSource tableView:tool.tableView
                                            objectValueForTableColumn:tool.tableView.tableColumns[0]
                                                        row:0];
    XCTAssertEqualObjects([object string], @"/dir");

    object = [tool.tableView.dataSource tableView:tool.tableView
                        objectValueForTableColumn:tool.tableView.tableColumns[0]
                                              row:1];
    XCTAssertEqualObjects([object string], @"/tmp");
}

- (void)testDirectoriesInsertsDirectoryNameOnDoubleClick {
    [self sendPromptAndStartCommand:@"make" toSession:_session];

    ToolDirectoriesView *tool =
        (ToolDirectoriesView *)[_view.toolbelt toolWithName:kRecentDirectoriesToolName];
    [tool.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    tool.toolWrapper.delegate.delegate = self;
    [tool.tableView.delegate performSelector:tool.tableView.doubleAction withObject:tool.tableView];
    XCTAssertEqualObjects(_insertedText, _currentDir);
}

#pragma mark Window

- (void)testToolbeltImpingesOnWindowWhenNearRightEdge {
    // Hide toolbelt
    [_windowController toggleToolbeltVisibility:nil];

    XCTAssert(!_view.shouldShowToolbelt);

    // Ensure the window fills the visible frame
    [_windowController.window setFrame:_windowController.window.screen.visibleFrame display:YES];
    NSRect originalWindowFrame = _windowController.window.frame;
    NSRect originalTabViewFrame = _view.tabView.frame;

    // Show toolbelt
    [_windowController toggleToolbeltVisibility:nil];

    // Window frame should not change
    XCTAssertEqual(_windowController.window.frame.size.width, originalWindowFrame.size.width);

    // TabView's frame should change
    XCTAssertNotEqual(_view.tabView.frame.size.width, originalTabViewFrame.size.width);
}

- (void)testToolbeltGrowsWhenSpaceIsAvailableOnRight {
    // Hide toolbelt
    [_windowController toggleToolbeltVisibility:nil];

    XCTAssert(!_view.shouldShowToolbelt);

    // Ensure the window has space on right
    NSRect newWindowFrame = _windowController.window.screen.visibleFrame;
    newWindowFrame.size.width -= 300;
    [_windowController.window setFrame:newWindowFrame display:YES];
    NSRect originalWindowFrame = _windowController.window.frame;
    NSRect originalTabViewFrame = _view.tabView.frame;

    // Show toolbelt
    [_windowController toggleToolbeltVisibility:nil];

    // Window frame should change
    XCTAssertNotEqual(_windowController.window.frame.size.width, originalWindowFrame.size.width);

    // TabView's frame should not
    XCTAssertEqual(_view.tabView.frame.size.width, originalTabViewFrame.size.width);
}

#pragma mark - iTermToolbeltViewDelegate

- (CGFloat)growToolbeltBy:(CGFloat)amount {
    return amount;
}

- (void)toolbeltUpdateMouseCursor {
}

- (void)toolbeltInsertText:(NSString *)text {
    [_insertedText appendString:text];
}

- (VT100RemoteHost *)toolbeltCurrentHost {
    return nil;
}

- (pid_t)toolbeltCurrentShellProcessId {
    return 0;
}

- (VT100ScreenMark *)toolbeltLastCommandMark {
    return nil;
}

- (void)toolbeltDidSelectMark:(iTermMark *)mark {
}

- (void)toolbeltActivateTriggerForCapturedOutputInCurrentSession:(CapturedOutput *)capturedOutput {
}

- (BOOL)toolbeltCurrentSessionHasGuid:(NSString *)guid {
    return NO;
}

- (NSArray<iTermCommandHistoryCommandUseMO *> *)toolbeltCommandUsesForCurrentSession {
    return @[];
}

- (void)toolbeltDidFinishGrowing {
}

@end
