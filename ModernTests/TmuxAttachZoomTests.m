//
//  TmuxAttachZoomTests.m
//  ModernTests
//
//  A window that is zoomed in tmux stays zoomed when iTerm2 attaches, but only with tmux 3.3 and
//  later. With tmux 2.8 the zoomed pane kept stale content from before the zoom until its program
//  redrew, so older versions unzoom the window as before.
//

#import <XCTest/XCTest.h>

#import "TmuxGatewayTestFakes.h"
#import "TmuxWindowOpener.h"

@interface TmuxGateway (TmuxAttachZoomTests)
- (void)enableWrites;
@end

@interface TmuxAttachZoomTests : XCTestCase
@end

@implementation TmuxAttachZoomTests {
    TmuxFakeGatewayDelegate *_delegate;
    TmuxRecordingGateway *_gateway;
}

- (void)setUp {
    [super setUp];
    _delegate = [[TmuxFakeGatewayDelegate alloc] init];
    _gateway = [[TmuxRecordingGateway alloc] initWithDelegate:_delegate dcsID:@"dcs"];
    [_gateway enableWrites];
}

- (NSString *)commandsSentToOpenZoomedWindowWithVersion:(NSString *)version
                                          visibleLayout:(NSString *)visibleLayout {
    _gateway.minimumServerVersion = [NSDecimalNumber decimalNumberWithString:version];
    TmuxWindowOpener *opener = [TmuxWindowOpener windowOpener];
    opener.windowIndex = 3;
    opener.layout = @"b25f,80x24,0,0{40x24,0,0,1,39x24,41,0,2}";
    opener.visibleLayout = visibleLayout;
    opener.zoomed = @YES;
    opener.gateway = _gateway;
    XCTAssertTrue([opener openWindows:YES]);
    return [_delegate.writtenStrings componentsJoinedByString:@""];
}

- (void)testZoomedWindowStaysZoomedWithTmux33 {
    NSString *written = [self commandsSentToOpenZoomedWindowWithVersion:@"3.3"
                                                          visibleLayout:@"abcd,80x24,0,0,2"];
    XCTAssertFalse([written containsString:@"resize-pane -Z"], @"%@", written);
}

- (void)testZoomedWindowIsUnzoomedWithTmux28 {
    NSString *written = [self commandsSentToOpenZoomedWindowWithVersion:@"2.8"
                                                          visibleLayout:@"abcd,80x24,0,0,2"];
    XCTAssertTrue([written containsString:@"resize-pane -Z -t @3"], @"%@", written);
}

- (void)testZoomedWindowWithoutVisibleLayoutIsUnzoomed {
    NSString *written = [self commandsSentToOpenZoomedWindowWithVersion:@"3.8" visibleLayout:@""];
    XCTAssertTrue([written containsString:@"resize-pane -Z -t @3"], @"%@", written);
}

@end
