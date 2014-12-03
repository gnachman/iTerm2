//
//  iTermPasteHelperTest.m
//  iTerm2
//
//  Created by George Nachman on 12/3/14.
//
//

#import "iTermPasteHelperTest.h"
#import "iTermPasteHelper.h"
#import "PasteEvent.h"

static NSString *const kTestString = @"a (\t\r\r\n" @"\x16" @"b";

@implementation iTermPasteHelperTest

- (void)sanitizeString:(NSString *)string
                expect:(NSString *)expected
                 flags:(iTermPasteFlags)flags
          tabTransform:(iTermTabTransformTags)tabTransform
          spacesPerTab:(int)spacesPerTab {
  PasteEvent *event = [PasteEvent pasteEventWithString:string
                                                 flags:flags
                                      defaultChunkSize:1
                                              chunkKey:nil
                                          defaultDelay:1
                                              delayKey:nil
                                          tabTransform:tabTransform
                                          spacesPerTab:spacesPerTab];
  [iTermPasteHelper sanitizePasteEvent:event encoding:NSUTF8StringEncoding];
  assert([expected isEqualToString:event.string]);
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
                expect:@"a\\ \\(\t\r\r\n" @"\x16" @"b"
                 flags:kPasteFlagsEscapeSpecialCharacters
          tabTransform:kTabTransformNone
          spacesPerTab:0];
}

- (void)testSanitizeSanitizingNewlines {
  [self sanitizeString:kTestString
                expect:@"a (\t\r\r" @"\x16" @"b"
                 flags:kPasteFlagsSanitizingNewlines
          tabTransform:kTabTransformNone
          spacesPerTab:0];
}

- (void)testSanitizeRemovingUnsafeControlCodes {
  [self sanitizeString:kTestString
                expect:@"a (\t\r\r\nb"
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

- (void)testSanitizeAllFlagsOn {
  // Test string gets transformed to @"a\\ \\(\t\r\rb"
  [self sanitizeString:kTestString
                expect:@"YVwgXCgJDQ1i\r"
                 flags:(kPasteFlagsEscapeSpecialCharacters |
                        kPasteFlagsSanitizingNewlines |
                        kPasteFlagsRemovingUnsafeControlCodes |
                        kPasteFlagsBracket |
                        kPasteFlagsBase64Encode)
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

@end
