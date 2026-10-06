//
//  TmuxGatewayTestFakes.h
//  ModernTests
//
//  Fakes for driving a TmuxGateway (and a TmuxController on top of it) with recorded control-mode
//  lines, without a tmux server.
//

#import <Cocoa/Cocoa.h>

#import "TmuxGateway.h"

NS_ASSUME_NONNULL_BEGIN

// Records aborts instead of showing a modal alert and detaching. A real abort's alert would hang
// the test run.
@interface TmuxRecordingGateway : TmuxGateway
@property(nonatomic, copy, nullable) NSString *abortMessage;

// Feeds one line of control-mode output, as the terminal's parser would.
- (void)feedLine:(NSString *)line;
- (void)feedLines:(NSArray<NSString *> *)lines;
@end

@interface TmuxFakeGatewayDelegate : NSObject<TmuxGatewayDelegate>
@property(nonatomic) BOOL sawLayoutChange;
@property(nonatomic, copy, nullable) NSString *layout;
@property(nonatomic, copy, nullable) NSString *visibleLayout;
@property(nonatomic, strong, nullable) NSNumber *zoomed;
@property(nonatomic, readonly) NSMutableArray<NSString *> *writtenStrings;
@end

NS_ASSUME_NONNULL_END
