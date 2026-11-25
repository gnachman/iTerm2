//
//  StatusBarNullabilityTests.m
//  ModernTests
//
//  Documents status bar nullability claims that the nullability sanitizer
//  found false (unit N8 of docs/swift-migration/nullability-triage.md) where
//  the declaration is not visible to Swift. Before the claims were made
//  nullable, each nil here was a -Wnonnull warning or a nullability
//  sanitizer report.
//

#import <XCTest/XCTest.h>

#import "iTermStatusBarLayoutAlgorithm.h"
#import "iTermStatusBarTextComponent.h"

// Declared here, not imported: the category is in Swift since its port, and
// ModernTests cannot import iTerm2SharedARC-Swift.h.
@interface NSImageView (StatusBarNullabilityTests)
- (void)it_setTintColor:(nullable NSColor *)color;
@end

// Declared only in iTermStatusBarTextComponent.m.
@interface iTermStatusBarTextComponent (StatusBarNullabilityTests)
- (nullable NSColor *)textColor;
- (nullable NSColor *)backgroundColor;
@end

@interface StatusBarNullabilityTests : XCTestCase
@end

@implementation StatusBarNullabilityTests

// The container view passes the component's text color, or its delegate's,
// and both can be nil. A nil tint clears the image view's tint.
- (void)testSetTintColorToNilClearsTheTint {
    NSImageView *imageView = [[NSImageView alloc] init];
    imageView.contentTintColor = [NSColor redColor];
    [imageView it_setTintColor:nil];
    XCTAssertNil(imageView.contentTintColor);
}

// The status bar view controller passes its mandatory view, which is nil
// when no component must stay visible; the algorithm tests it before use.
- (void)testLayoutAlgorithmWithoutMandatoryView {
    iTermStatusBarLayoutAlgorithm *algorithm =
        [iTermStatusBarLayoutAlgorithm layoutAlgorithmWithContainerViews:@[]
                                                           mandatoryView:nil
                                                          statusBarWidth:100
                                                                 setting:iTermStatusBarLayoutAlgorithmSettingStable
                                                   removeEmptyComponents:NO];
    XCTAssertNotNil(algorithm);
    XCTAssertNil(algorithm.mandatoryView);
    XCTAssertEqual(algorithm.visibleContainerViews.count, 0);
}

// With no knob values, no default text color, no delegate and no advanced
// configuration, a text component has neither a text color nor a
// background color.
- (void)testTextComponentWithoutColorsHasNone {
    iTermStatusBarTextComponent *component = [[iTermStatusBarTextComponent alloc] initWithConfiguration:@{}
                                                                                                  scope:nil];
    XCTAssertNil([component textColor]);
    XCTAssertNil([component backgroundColor]);
}

@end
