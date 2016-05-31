//
//  iTermPasteHelperTest.m
//  iTerm2
//
//  Created by George Nachman on 12/3/14.
//
//

#import "iTermApplicationDelegate.h"
#import "iTermPasteHelper.h"
#import "iTermWarning.h"
#import "NSData+iTerm.h"
#import "NSStringITerm.h"
#import "PasteEvent.h"
#import "PasteboardHistory.h"
#import <XCTest/XCTest.h>

typedef NSModalResponse (^WarningBlockType)(NSAlert *alert, NSString *identifier);

static NSString *const kTestString = @"a (\t\r\r\n" @"\x16" @"“”‘’–—b";
static NSString *const kHelloWorld = @"Hello World";
static const double kFloatingPointTolerance = 0.00001;

@interface iTermPasteHelperTest : XCTestCase
@end

@interface iTermInstrumentedPasteHelper : iTermPasteHelper
@property(nonatomic, assign) NSTimer *timer;
@property(nonatomic, assign) NSTimeInterval duration;
- (void)fireTimer;
@end

@implementation iTermInstrumentedPasteHelper

- (NSTimer *)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                     target:(id)aTarget
                                   selector:(SEL)aSelector
                                   userInfo:(id)userInfo
                                    repeats:(BOOL)yesOrNo {
    _duration += ti;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:ti
                                                  target:aTarget
                                                selector:aSelector
                                                userInfo:userInfo
                                                 repeats:yesOrNo];
    return self.timer;
}

- (void)fireTimer {
    NSTimer *timer = _timer;
    self.timer = nil;
    [timer fire];
}

@end

@interface iTermPasteHelperTest()<iTermPasteHelperDelegate, iTermWarningHandler>
@end

@implementation iTermPasteHelperTest {
    NSMutableString *_writeBuffer;
    BOOL _shouldBracket;
    BOOL _isAtShellPrompt;
    iTermInstrumentedPasteHelper *_helper;
    WarningBlockType _warningBlock;
}

- (void)setUp {
    _writeBuffer = [[[NSMutableString alloc] init] autorelease];
    _shouldBracket = NO;
    _isAtShellPrompt = NO;
    _helper = [[[iTermInstrumentedPasteHelper alloc] init] autorelease];
    _helper.delegate = self;
    [iTermWarning setWarningHandler:self];
    [[PasteboardHistory sharedInstance] clear];
    _warningBlock = [^NSModalResponse(NSAlert *alert, NSString *identifier) {
        if ([identifier isEqualToString:kMultiLinePasteWarningUserDefaultsKey]) {
            return 1;  /* deprecated NSAlertDefaultReturn; */
        }
        XCTAssert(false);
    } copy];
}

- (void)tearDown {
    [iTermWarning setWarningHandler:nil];
    [_warningBlock release];
}

- (void)runTimer {
    while (_helper.timer) {
        [_helper fireTimer];
    }
}

- (void)sanitizeString:(NSString *)string
                expect:(NSString *)expected
                 flags:(iTermPasteFlags)flags
          tabTransform:(iTermTabTransformTags)tabTransform
          spacesPerTab:(int)spacesPerTab {
  [self sanitizeString:string
                expect:expected
                 flags:flags
          tabTransform:tabTransform
          spacesPerTab:spacesPerTab
                 regex:nil
          substitution:nil];
}

- (void)sanitizeString:(NSString *)string
                expect:(NSString *)expected
                 flags:(iTermPasteFlags)flags
          tabTransform:(iTermTabTransformTags)tabTransform
          spacesPerTab:(int)spacesPerTab
                 regex:(NSString *)regex
          substitution:(NSString *)substitution {
    PasteEvent *event = [PasteEvent pasteEventWithString:string
                                                   flags:flags
                                        defaultChunkSize:1
                                                chunkKey:nil
                                            defaultDelay:1
                                                delayKey:nil
                                            tabTransform:tabTransform
                                            spacesPerTab:spacesPerTab
                                                   regex:regex
                                            substitution:substitution];
    [iTermPasteHelper sanitizePasteEvent:event encoding:NSUTF8StringEncoding];
    XCTAssert([expected isEqualToString:event.string]);
}

- (void)testSanitizeIdentity {
    [self sanitizeString:kTestString
                  expect:kTestString
                   flags:0
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeEscapeSpecialCharacters {
    [self sanitizeString:kTestString
                  expect:@"a\\ \\(\t\r\r\n" @"\x16" @"“”‘’–—b"
                   flags:kPasteFlagsEscapeSpecialCharacters
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeSanitizingNewlines {
    [self sanitizeString:kTestString
                  expect:@"a (\t\r\r" @"\x16" @"“”‘’–—b"
                   flags:kPasteFlagsSanitizingNewlines
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeRemovingUnsafeControlCodes {
    [self sanitizeString:kTestString
                  expect:@"a (\t\r\r\n“”‘’–—b"
                   flags:kPasteFlagsRemovingUnsafeControlCodes
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeBracket {
    [self sanitizeString:kTestString
                  expect:kTestString
                   flags:0
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeBase64Encode {
    [self sanitizeString:@"Hello"
                  expect:@"SGVsbG8=\r"
                   flags:kPasteFlagsBase64Encode
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeQuotes {
    [self sanitizeString:@"a“”‘’–—b"
                  expect:@"a\"\"''--b"
                   flags:kPasteFlagsConvertUnicodePunctuation
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeAllFlagsOn {
    NSString *expectedString = @"a\\ \\(\t\r\r\\\"\\\"\\'\\'--b";
    NSData *data = [expectedString dataUsingEncoding:NSUTF8StringEncoding];
    NSString *expected = [data stringWithBase64EncodingWithLineBreak:@"\r"];
    [self sanitizeString:kTestString
                  expect:expected
                   flags:(kPasteFlagsEscapeSpecialCharacters |
                          kPasteFlagsSanitizingNewlines |
                          kPasteFlagsRemovingUnsafeControlCodes |
                          kPasteFlagsBracket |
                          kPasteFlagsBase64Encode |
                          kPasteFlagsConvertUnicodePunctuation)
            tabTransform:kTabTransformNone
            spacesPerTab:0];
}

- (void)testSanitizeTabsToSpaces {
    [self sanitizeString:@"a\tb"
                  expect:@"a    b"
                   flags:0
            tabTransform:kTabTransformConvertToSpaces
            spacesPerTab:4];
}

- (void)testSanitizeEscapeTabsCtrlV {
    [self sanitizeString:@"a\tb"
                  expect:@"a" @"\x16" @"\tb"
                   flags:0
            tabTransform:kTabTransformEscapeWithCtrlV
            spacesPerTab:4];
}

- (void)testBasicPasteString {
    [_helper pasteString:kHelloWorld
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    XCTAssert([_writeBuffer isEqualToString:kHelloWorld]);
    XCTAssert(_helper.duration == 0);
    XCTAssert([[[[PasteboardHistory sharedInstance] entries][0] mainValue] isEqualToString:kHelloWorld]);
}

- (void)testDefaultFlagsOnPasteString {
    [_helper pasteString:kTestString
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    NSString *expected = @"a (\t\r\r“”‘’–—b";
    XCTAssert([_writeBuffer isEqualToString:expected]);
}

- (void)testPasteStringWithFlagsAndConvertToSpacesTabTransform {
    [_helper pasteString:kTestString
                  slowly:NO
        escapeShellChars:YES
                commands:NO
            tabTransform:kTabTransformConvertToSpaces
            spacesPerTab:4];
    [self runTimer];
    NSString *expected = @"a\\ \\(    \r\r“”‘’–—b";
    XCTAssert([_writeBuffer isEqualToString:expected]);
}

- (void)testPasteStringWithFlagsAndCtrlVTabTransform {
    [_helper pasteString:kTestString
                  slowly:NO
        escapeShellChars:YES
                commands:NO
            tabTransform:kTabTransformEscapeWithCtrlV
            spacesPerTab:0];
    [self runTimer];
    NSString *expected = @"a\\ \\(\x16\t\r\r“”‘’–—b";
    XCTAssert([_writeBuffer isEqualToString:expected]);
}

- (void)testMultilineWarning {
    __block BOOL warned = NO;
    [_warningBlock release];
    _warningBlock = [^NSModalResponse(NSAlert *alert, NSString *identifier) {
        XCTAssert([identifier isEqualToString:kMultiLinePasteWarningUserDefaultsKey]);
        warned = YES;
        return 1;  /* deprecated NSAlertDefaultReturn; */
    } copy];

    // Check cr newline
    [_helper pasteString:@"line 1\rline 2"
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    XCTAssert(warned);

    // Check lf newline
    warned = NO;
    [_helper pasteString:@"line 1\nline 2"
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    XCTAssert(warned);

    // Check crlf newline
    warned = NO;
    [_helper pasteString:@"line 1\r\nline 2"
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    XCTAssert(warned);

    // Check no newline gives no warning.
    warned = NO;
    [_helper pasteString:@"line 1"
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    XCTAssert(!warned);
}

- (void)testBracketingOnPasteString {
    _shouldBracket = YES;
    [_helper pasteString:kHelloWorld
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    NSString *expected = @"\x1b[200~Hello World\x1b[201~";
    XCTAssert([_writeBuffer isEqualToString:expected]);
    XCTAssert([[[[PasteboardHistory sharedInstance] entries][0] mainValue] isEqualToString:kHelloWorld]);
}

// You still get a close bracket even if you change your mind about wanting it unless the whole paste
// is queued.
- (void)testDelegateChangesItsMindAboutBracketingNoQueue {
    NSString *test = [@" " stringRepeatedTimes:2000];
    _shouldBracket = YES;
    [_helper pasteString:test
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    _shouldBracket = NO;
    [self runTimer];
    NSString *expected = [[@"\x1b[200~" stringByAppendingString:test] stringByAppendingString:@"\x1b[201~"];
    XCTAssert([_writeBuffer isEqualToString:expected]);
    XCTAssert(fabs(_helper.duration - 0.01) < kFloatingPointTolerance);
}

- (void)testDelegateChangesItsMindAboutBracketingWithQueue {
    NSString *test1 = [@"1" stringRepeatedTimes:2000];
    _shouldBracket = YES;
    [_helper pasteString:test1
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    _shouldBracket = NO;

    NSString *test2 = [@"2" stringRepeatedTimes:2000];
    [_helper pasteString:test2
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];

    [self runTimer];
    NSString *expected = [[[@"\x1b[200~" stringByAppendingString:test1] stringByAppendingString:@"\x1b[201~"] stringByAppendingString:test2];
    XCTAssert([_writeBuffer isEqualToString:expected]);
}

- (void)testTwoChunkPasteString {
    NSString *test = [@" " stringRepeatedTimes:2000];
    [_helper pasteString:test
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    XCTAssert([_writeBuffer isEqualToString:test]);
    XCTAssert(fabs(_helper.duration - 0.01) < kFloatingPointTolerance);
}

- (void)testSlowTwoChunkPasteString {
    NSString *test = [@" " stringRepeatedTimes:20];
    [_helper pasteString:test
                  slowly:YES
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    XCTAssert([_writeBuffer isEqualToString:test]);
    XCTAssert(fabs(_helper.duration - 0.125) < kFloatingPointTolerance);
}

- (void)testPasteQueued {
    NSString *test1 = [@"1" stringRepeatedTimes:2000];
    [_helper pasteString:test1
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    NSString *test2 = [@"2" stringRepeatedTimes:2000];
    [_helper pasteString:test2
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    XCTAssert([_writeBuffer isEqualToString:[test1 stringByAppendingString:test2]]);
    NSTimeInterval expectedDuration = 2 * 0.01;
    XCTAssert(fabs(_helper.duration - expectedDuration) < kFloatingPointTolerance);
    XCTAssert([[[[PasteboardHistory sharedInstance] entries][0] mainValue] isEqualToString:test1]);
    XCTAssert([[[[PasteboardHistory sharedInstance] entries][1] mainValue] isEqualToString:test2]);
}

- (void)testQueuedKeystrokeAndPaste {
    NSString *test1 = [@"1" stringRepeatedTimes:2000];
    [_helper pasteString:test1
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [_helper enqueueEvent:[NSEvent keyEventWithType:NSKeyDown
                                           location:NSZeroPoint
                                      modifierFlags:0
                                          timestamp:[NSDate timeIntervalSinceReferenceDate]
                                       windowNumber:0
                                            context:nil
                                         characters:@"x"
                        charactersIgnoringModifiers:@"x"
                                          isARepeat:NO
                                            keyCode:0]];
    NSString *test2 = [@"2" stringRepeatedTimes:2000];
    [_helper pasteString:test2
                  slowly:NO
        escapeShellChars:NO
                commands:NO
            tabTransform:kTabTransformNone
            spacesPerTab:0];
    [self runTimer];
    XCTAssert([_writeBuffer isEqualToString:[[test1 stringByAppendingString:@"x"] stringByAppendingString:test2]]);
    NSTimeInterval expectedDuration = 2 * 0.01;
    XCTAssert(fabs(_helper.duration - expectedDuration) < kFloatingPointTolerance);
}

#pragma mark - iTermPasteHelperDelegate

- (void)pasteHelperWriteString:(NSString *)string {
    [_writeBuffer appendString:string];
}

- (void)pasteHelperKeyDown:(NSEvent *)event {
    [_writeBuffer appendString:[event characters]];
}

- (BOOL)pasteHelperShouldBracket {
    return _shouldBracket;
}

- (NSStringEncoding)pasteHelperEncoding {
    return NSUTF8StringEncoding;
}

- (NSView *)pasteHelperViewForIndicator {
    return nil;
}

- (BOOL)pasteHelperIsAtShellPrompt {
    return _isAtShellPrompt;
}

- (BOOL)pasteHelperCanWaitForPrompt {
    return NO;
}

#pragma mark - iTermWarningHandler

- (NSModalResponse)warningWouldShowAlert:(NSAlert *)alert identifier:(NSString *)identifier {
    return _warningBlock(alert, identifier);
}

@end
