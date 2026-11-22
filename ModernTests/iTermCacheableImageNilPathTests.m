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
//  its behavior around such a call. They were written in Objective-C before
//  the header was visible to Swift.
//

#import <XCTest/XCTest.h>

// A Swift class (sources/SessionIcons/iTermCacheableImage.swift). ModernTests
// cannot import iTerm2SharedARC-Swift.h, so declare what these tests call.
@interface iTermCacheableImage : NSObject
- (nullable NSImage *)imageAtPath:(nullable NSString *)path ofSize:(NSSize)size flipped:(BOOL)flipped;
@end

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

// The header declares the path nullable, so nil is passed directly.
- (NSImage *)imageFromCache:(iTermCacheableImage *)cache withNilPathOfSize:(NSSize)size {
    return [cache imageAtPath:nil ofSize:size flipped:NO];
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

// The cache keeps a copy of the path, so mutating the string that was passed
// in does not change the cached key. Swift cannot exercise this: a mutable
// string passed from Swift is bridged to a new string at the call.
- (void)testMutatingThePassedPathDoesNotChangeTheCachedKey {
    iTermCacheableImage *cache = [[iTermCacheableImage alloc] init];
    NSString *a = [self writeImageNamed:@"a.png"];
    NSString *b = [self writeImageNamed:@"b.png"];
    NSMutableString *mutablePath = [a mutableCopy];
    NSImage *first = [cache imageAtPath:mutablePath ofSize:NSMakeSize(16, 16) flipped:NO];
    XCTAssertNotNil(first);

    [mutablePath setString:b];

    XCTAssertTrue([cache imageAtPath:[a copy] ofSize:NSMakeSize(16, 16) flipped:NO] == first);
}

@end
