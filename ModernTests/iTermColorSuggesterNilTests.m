//
//  iTermColorSuggesterNilTests.m
//  ModernTests
//
//  iTermColorSuggester's one caller passes -[iTermColorMap colorForKey:],
//  which returns nil for a key the map lacks, although the class's header
//  declares the colors nonnull. In Objective-C a nil default background is
//  messaged with -labColor, which gives a zero struct: lightness 0, as for
//  black. A nil default text color is never used. These tests pin both
//  through Objective-C, which can pass nil where Swift cannot.
//

#import <XCTest/XCTest.h>

// Declared here, not imported, so that these tests survive the port of the
// class to Swift; ModernTests cannot import iTerm2SharedARC-Swift.h. The
// colors are nullable here because these tests pass nil.
NS_ASSUME_NONNULL_BEGIN
@interface iTermColorSuggester : NSObject
@property (nonatomic, readonly) NSColor *suggestedTextColor;
@property (nonatomic, readonly) NSColor *suggestedBackgroundColor;
- (instancetype)initWithDefaultTextColor:(nullable NSColor *)defaultTextColor
                  defaultBackgroundColor:(nullable NSColor *)defaultBackgroundColor
                       minimumDifference:(CGFloat)minimumDifference
                                    seed:(long)seed;
@end
NS_ASSUME_NONNULL_END

@interface iTermColorSuggesterNilTests : XCTestCase
@end

@implementation iTermColorSuggesterNilTests

- (NSArray<NSNumber *> *)components:(NSColor *)color {
    NSColor *srgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    return @[ @(srgb.redComponent), @(srgb.greenComponent), @(srgb.blueComponent), @(srgb.alphaComponent) ];
}

- (void)testNilDefaultBackgroundActsAsBlack {
    NSColor *black = [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:1];
    NSColor *white = [NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:1];
    for (long seed = 0; seed < 10; seed++) {
        iTermColorSuggester *withNil = [[iTermColorSuggester alloc] initWithDefaultTextColor:white
                                                                      defaultBackgroundColor:nil
                                                                           minimumDifference:0.4
                                                                                        seed:seed];
        iTermColorSuggester *withBlack = [[iTermColorSuggester alloc] initWithDefaultTextColor:white
                                                                        defaultBackgroundColor:black
                                                                             minimumDifference:0.4
                                                                                          seed:seed];
        XCTAssertNotNil(withNil.suggestedTextColor);
        XCTAssertNotNil(withNil.suggestedBackgroundColor);
        XCTAssertEqualObjects([self components:withNil.suggestedTextColor],
                              [self components:withBlack.suggestedTextColor], @"seed %ld", seed);
        XCTAssertEqualObjects([self components:withNil.suggestedBackgroundColor],
                              [self components:withBlack.suggestedBackgroundColor], @"seed %ld", seed);
    }
}

- (void)testNilDefaultTextColorIsAccepted {
    NSColor *gray = [NSColor colorWithSRGBRed:0.5 green:0.5 blue:0.5 alpha:1];
    NSColor *red = [NSColor colorWithSRGBRed:1 green:0 blue:0 alpha:1];
    iTermColorSuggester *withNil = [[iTermColorSuggester alloc] initWithDefaultTextColor:nil
                                                                  defaultBackgroundColor:gray
                                                                       minimumDifference:0.25
                                                                                    seed:9];
    iTermColorSuggester *withRed = [[iTermColorSuggester alloc] initWithDefaultTextColor:red
                                                                  defaultBackgroundColor:gray
                                                                       minimumDifference:0.25
                                                                                    seed:9];
    XCTAssertEqualObjects([self components:withNil.suggestedTextColor],
                          [self components:withRed.suggestedTextColor]);
    XCTAssertEqualObjects([self components:withNil.suggestedBackgroundColor],
                          [self components:withRed.suggestedBackgroundColor]);
}

@end
