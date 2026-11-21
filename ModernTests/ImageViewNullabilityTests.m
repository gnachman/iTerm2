//
//  ImageViewNullabilityTests.m
//  ModernTests
//
//  -[iTermImageView image] returns the lower view's image, nil when a session
//  has no background image, under a nonnull claim (unit N10 of
//  docs/swift-migration/nullability-triage.md). The header is not visible to
//  Swift, so the claim is pinned here in Objective-C. Before the claim was
//  made nullable, setting nil here was a -Wnonnull warning.
//

#import <XCTest/XCTest.h>

#import "iTermImageView.h"

@interface ImageViewNullabilityTests : XCTestCase
@end

@implementation ImageViewNullabilityTests

- (void)testImageViewWithoutImageHasNone {
    iTermImageView *imageView = [[iTermImageView alloc] init];
    XCTAssertNil(imageView.image);
}

// Clearing the image is allowed and leaves none.
- (void)testSettingNilImageClearsIt {
    iTermImageView *imageView = [[iTermImageView alloc] init];
    imageView.image = nil;
    XCTAssertNil(imageView.image);
}

@end
