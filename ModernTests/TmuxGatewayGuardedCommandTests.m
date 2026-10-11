//
//  TmuxGatewayGuardedCommandTests.m
//  ModernTests
//
//  A guarded command is one `if -F` whose branches are each one command. tmux sends a reply block
//  for the `if` and another for the branch it ran, unless the `if` itself fails (its -t target is
//  gone), in which case there is only the first. The gateway pairs reply blocks with queued
//  commands one to one, so it must expect two blocks and still stay in step when only one comes.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>

#import "TmuxGateway.h"
#import "VT100Token.h"

// Defined in TmuxGatewayExitInResponseTests.m.
@interface TmuxGatewayExitInResponseFakeDelegate : NSObject<TmuxGatewayDelegate>
@property(nonatomic) BOOL hostDisconnected;
@end

@interface TmuxGatewayGuardedCommandTests : XCTestCase
@end

@implementation TmuxGatewayGuardedCommandTests {
    TmuxGatewayExitInResponseFakeDelegate *_delegate;
    TmuxGateway *_gateway;
    NSMutableArray<NSString *> *_guardReplies;
    NSMutableArray<NSString *> *_otherReplies;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxGatewayExitInResponseFakeDelegate alloc] init];
    _gateway = [[TmuxGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:@"3.2"];
    _guardReplies = [NSMutableArray array];
    _otherReplies = [NSMutableArray array];
}

- (void)handleGuardReply:(NSString *)reply {
    [_guardReplies addObject:reply ?: @"(nil)"];
}

- (void)handleOtherReply:(NSString *)reply {
    [_otherReplies addObject:reply ?: @"(nil)"];
}

- (void)feed:(NSArray<NSString *> *)lines {
    for (NSString *line in lines) {
        VT100Token *token = [[VT100Token alloc] init];
        token.type = TMUX_LINE;
        token.string = line;
        token.savedData = [line dataUsingEncoding:NSUTF8StringEncoding];
        [_gateway executeToken:token];
    }
}

// A guarded command followed by an ordinary one, so each test also checks the queue stays in step.
- (void)sendGuardedThenOther {
    [_gateway sendGuardedCommand:@"if -F -t @9 '1' 'swap-pane -d -s %1 -t %3' 'display -p iterm2_wg_guard_failed'"
                  responseTarget:self
                responseSelector:@selector(handleGuardReply:)
                  responseObject:nil];
    [_gateway sendCommand:@"list-windows"
           responseTarget:self
         responseSelector:@selector(handleOtherReply:)];
}

- (void)testActionRan {
    [self sendGuardedThenOther];
    [self feed:@[ @"%begin 1 1 1", @"%end 1 1 1",
                  @"%begin 1 2 1", @"%end 1 2 1",
                  @"%begin 1 3 1", @"@1", @"%end 1 3 1" ]];
    XCTAssertEqualObjects(_guardReplies, @[ @"" ]);
    XCTAssertEqualObjects(_otherReplies, @[ @"@1" ]);
    XCTAssertFalse(_delegate.hostDisconnected);
}

- (void)testGuardDidNotHold {
    [self sendGuardedThenOther];
    [self feed:@[ @"%begin 1 1 1", @"%end 1 1 1",
                  @"%begin 1 2 1", @"iterm2_wg_guard_failed", @"%end 1 2 1",
                  @"%begin 1 3 1", @"@1", @"%end 1 3 1" ]];
    XCTAssertEqualObjects(_guardReplies, @[ @"iterm2_wg_guard_failed" ]);
    XCTAssertEqualObjects(_otherReplies, @[ @"@1" ]);
}

- (void)testActionFailed {
    [self sendGuardedThenOther];
    [self feed:@[ @"%begin 1 1 1", @"%end 1 1 1",
                  @"%begin 1 2 1", @"can't find pane: %3", @"%error 1 2 1",
                  @"%begin 1 3 1", @"@1", @"%end 1 3 1" ]];
    XCTAssertEqualObjects(_guardReplies, @[ @"(nil)" ]);
    XCTAssertEqualObjects(_otherReplies, @[ @"@1" ]);
    XCTAssertFalse(_delegate.hostDisconnected);
}

// The `if` cannot find its target, so no branch runs and tmux sends one block, not two.
- (void)testGuardItselfFailed {
    [self sendGuardedThenOther];
    [self feed:@[ @"%begin 1 1 1", @"can't find window: @9", @"%error 1 1 1",
                  @"%begin 1 2 1", @"@1", @"%end 1 2 1" ]];
    XCTAssertEqualObjects(_guardReplies, @[ @"(nil)" ]);
    XCTAssertEqualObjects(_otherReplies, @[ @"@1" ]);
    XCTAssertFalse(_delegate.hostDisconnected);
}

@end
