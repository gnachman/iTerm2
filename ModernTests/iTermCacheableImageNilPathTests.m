//
//  iTermCacheableImageNilPathTests.m
//  ModernTests
//
//  -[iTermCacheableImage imageAtPath:ofSize:flipped:] can receive a nil path:
//  its one caller passes +[iTermProfilePreferences stringForKey:inProfile:],
//  which is declared nullable. The method used to pass that nil on to
//  -[NSImage initWithContentsOfFile:], whose parameter AppKit declares
//  nonnull; that returned nil, but the nullability sanitizer aborts on it.
//  These tests pin the result for a nil path (nil) and that the cache keeps
//  its behavior around such a call. The header is not visible to Swift, so
//  they are written in Objective-C. See
//  docs/swift-migration/units/iTermCacheableImage.md.
//

#import <XCTest/XCTest.h>

#import "iTermCacheableImage.h"

@interface iTermCacheableImageNilPathTests : XCTestCase
@end

@implementation iTermCacheableImageNilPathTests {
    NSString *_directory;
}

- (void)setUp {
    [super setUp];
    _directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:_directory
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error], @"%@", error);
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_directory error:nil];
    [super tearDown];
}

// Writes a 16x16 opaque PNG and returns its path.
- (NSString *)writeImageNamed:(NSString *)name {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:16
                                                                     pixelsHigh:16
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSDeviceRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0];
    memset(rep.bitmapData, 0xff, (size_t)rep.bytesPerRow * 16);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSString *path = [_directory stringByAppendingPathComponent:name];
    XCTAssertTrue([png writeToFile:path atomically:YES]);
    return path;
}

// The header still claims the path is nonnull, so a direct call with nil
// would be reported by the nullability sanitizer at this file's call site,
// before the method runs. An invocation carries the nil into the method
// without that check, so what the sanitizer sees is the method's own use of
// the path.
- (NSImage *)imageFromCache:(iTermCacheableImage *)cache withNilPathOfSize:(NSSize)size {
    SEL selector = @selector(imageAtPath:ofSize:flipped:);
    NSInvocation *invocation =
        [NSInvocation invocationWithMethodSignature:[cache methodSignatureForSelector:selector]];
    invocation.target = cache;
    invocation.selector = selector;
    __unsafe_unretained NSString *path = nil;
    BOOL flipped = NO;
    [invocation setArgument:&path atIndex:2];
    [invocation setArgument:&size atIndex:3];
    [invocation setArgument:&flipped atIndex:4];
    [invocation invoke];
    __unsafe_unretained NSImage *result = nil;
    [invocation getReturnValue:&result];
    return result;
}

- (void)testNilPathGivesNil {
    iTermCacheableImage *cache = [[iTermCacheableImage alloc] init];
    XCTAssertNil([self imageFromCache:cache withNilPathOfSize:NSMakeSize(16, 16)]);
    XCTAssertNil([self imageFromCache:cache withNilPathOfSize:NSMakeSize(16, 16)]);
}

- (void)testGoodPathLoadsAfterNilPath {
    iTermCacheableImage *cache = [[iTermCacheableImage alloc] init];
    XCTAssertNil([self imageFromCache:cache withNilPathOfSize:NSMakeSize(16, 16)]);

    NSString *good = [self writeImageNamed:@"a.png"];
    NSImage *image = [cache imageAtPath:good ofSize:NSMakeSize(16, 16) flipped:NO];
    XCTAssertNotNil(image);
    XCTAssertTrue(NSEqualSizes(image.size, NSMakeSize(16, 16)));
}

// A nil path replaces the cached entry: the same good path afterwards loads
// again and gives a new object.
- (void)testNilPathReplacesTheCachedImage {
    iTermCacheableImage *cache = [[iTermCacheableImage alloc] init];
    NSString *good = [self writeImageNamed:@"a.png"];
    NSImage *first = [cache imageAtPath:good ofSize:NSMakeSize(16, 16) flipped:NO];
    XCTAssertNotNil(first);
    XCTAssertTrue([cache imageAtPath:good ofSize:NSMakeSize(16, 16) flipped:NO] == first);

    XCTAssertNil([self imageFromCache:cache withNilPathOfSize:NSMakeSize(16, 16)]);

    NSImage *again = [cache imageAtPath:good ofSize:NSMakeSize(16, 16) flipped:NO];
    XCTAssertNotNil(again);
    XCTAssertTrue(again != first);
}

@end
