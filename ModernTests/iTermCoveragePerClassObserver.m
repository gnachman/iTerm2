//
//  iTermCoveragePerClassObserver.m
//  ModernTests
//
//  Per-class coverage profiles in a single test run, for
//  tools/swift_migration/coverage_tests.sh --observer (the map from source
//  file to the test classes that execute it, docs/swift-migration/test-speed.md
//  section 2 item 7).
//
//  Inert unless the test host's environment has ITERM2_COVERAGE_PER_CLASS_DIR
//  and an LLVM_PROFILE_FILE in continuous mode (%c) with the process id (%p),
//  which only coverage_tests.sh --observer sets. Otherwise +load returns
//  before registering anything and nothing else in this file runs.
//
//  When active: each image built with -fprofile-instr-generate has its own
//  private copy of the profile runtime, so the test bundle cannot ask the
//  app's image to write its profile. In continuous mode, though, every
//  image's counter section is mapped onto its profile file. So when a test
//  class starts, this zeroes the counter section of every loaded image, and
//  when it finishes, it copies this process's profile files into
//  $ITERM2_COVERAGE_PER_CLASS_DIR/<class>/. Each copy holds the counts made
//  while that class ran. The counts made while the app launched are copied
//  to <dir>/_launch before the first class.
//
//  Per-class attribution from an observer run is approximate: work a class
//  leaves running (an asyncAfter block, a timer, another thread) is counted
//  for the class that follows in the same process, and work the app's launch
//  leaves running is counted for whichever class is running when it
//  happens. It once made 14
//  functions appear exercised by the wrong class. So
//  tools/swift_migration/coverage_report.py tests-for on such a run lists
//  classes as "may execute" and exits 3; a per-class verdict needs
//  coverage_tests.sh --per-class, which runs each class in its own process.
//
//  The images to zero are tracked with _dyld_register_func_for_add_image and
//  _dyld_register_func_for_remove_image (registered only when active), under
//  a lock, so an image loaded or unloaded while counters are being zeroed
//  is never walked half-mapped.
//

#import <XCTest/XCTest.h>
#import <mach-o/dyld.h>
#import <os/lock.h>
#import <stdlib.h>
#import <mach-o/loader.h>
#import <string.h>
#import <unistd.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const iTermCoveragePerClassDirectoryKey = @"ITERM2_COVERAGE_PER_CLASS_DIR";

@interface iTermCoveragePerClassObserver : NSObject <XCTestObservation>
+ (nullable NSString *)outputDirectoryForEnvironment:(NSDictionary<NSString *, NSString *> *)environment;
+ (BOOL)isRegistered;
@end

static iTermCoveragePerClassObserver *sRegisteredObserver;

// The loaded 64-bit images, kept by dyld's add and remove callbacks
// (registered in +load only when the observer is active). Guarded by sImagesLock, which the remove
// callback also takes, so an image cannot be unmapped while its counters
// are being zeroed.
typedef struct {
    const struct mach_header_64 *header;
    intptr_t slide;
} iTermCoverageImage;

static os_unfair_lock sImagesLock = OS_UNFAIR_LOCK_INIT;
static iTermCoverageImage *sImages;
static size_t sImageCount;
static size_t sImageCapacity;

static void iTermCoverageImageAdded(const struct mach_header *mh, intptr_t slide) {
    if (!mh || mh->magic != MH_MAGIC_64) {
        return;
    }
    os_unfair_lock_lock(&sImagesLock);
    if (sImageCount == sImageCapacity) {
        const size_t capacity = sImageCapacity ? sImageCapacity * 2 : 256;
        iTermCoverageImage *grown = realloc(sImages, capacity * sizeof(iTermCoverageImage));
        if (!grown) {
            os_unfair_lock_unlock(&sImagesLock);
            return;
        }
        sImages = grown;
        sImageCapacity = capacity;
    }
    sImages[sImageCount++] = (iTermCoverageImage){ (const struct mach_header_64 *)mh, slide };
    os_unfair_lock_unlock(&sImagesLock);
}

static void iTermCoverageImageRemoved(const struct mach_header *mh, intptr_t slide) {
    (void)slide;
    os_unfair_lock_lock(&sImagesLock);
    for (size_t i = 0; i < sImageCount; i++) {
        if (sImages[i].header == (const struct mach_header_64 *)mh) {
            sImages[i] = sImages[--sImageCount];
            break;
        }
    }
    os_unfair_lock_unlock(&sImagesLock);
}

@implementation iTermCoveragePerClassObserver {
    NSString *_outputDirectory;
    NSString *_profileDirectory;
    NSString *_profilePrefix;
    BOOL _launchSaved;
}

// The directory to write to, or nil when the observer must stay inert.
+ (nullable NSString *)outputDirectoryForEnvironment:(NSDictionary<NSString *, NSString *> *)environment {
    NSString *dir = environment[iTermCoveragePerClassDirectoryKey];
    if (dir.length == 0) {
        return nil;
    }
    NSString *profileFile = environment[@"LLVM_PROFILE_FILE"];
    if (![profileFile containsString:@"%c"] || ![profileFile containsString:@"%p"]) {
        NSLog(@"iTermCoveragePerClassObserver: %@ is set but LLVM_PROFILE_FILE (%@) lacks %%c or %%p; inert",
              iTermCoveragePerClassDirectoryKey, profileFile);
        return nil;
    }
    return dir;
}

+ (BOOL)isRegistered {
    return sRegisteredObserver != nil;
}

+ (void)load {
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    NSString *dir = [self outputDirectoryForEnvironment:environment];
    if (!dir) {
        return;
    }
    iTermCoveragePerClassObserver *observer = [[iTermCoveragePerClassObserver alloc] init];
    observer->_outputDirectory = dir;
    observer->_profileDirectory = [environment[@"LLVM_PROFILE_FILE"] stringByDeletingLastPathComponent];
    observer->_profilePrefix = [NSString stringWithFormat:@"%d-", getpid()];
    sRegisteredObserver = observer;
    // The add callback runs at once for every image already loaded, then for
    // each image loaded later.
    _dyld_register_func_for_add_image(iTermCoverageImageAdded);
    _dyld_register_func_for_remove_image(iTermCoverageImageRemoved);
    [[XCTestObservationCenter sharedTestObservationCenter] addTestObserver:observer];
}

// Zeroes the profile counters (and the MC/DC bitmaps, if any) of one image.
static void iTermCoverageZeroImage(const struct mach_header_64 *header, intptr_t slide) {
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t c = 0; c < header->ncmds; c++) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            const struct section_64 *sections = (const struct section_64 *)(segment + 1);
            for (uint32_t s = 0; s < segment->nsects; s++) {
                if (strncmp(sections[s].sectname, "__llvm_prf_cnts", sizeof(sections[s].sectname)) == 0 ||
                    strncmp(sections[s].sectname, "__llvm_prf_bits", sizeof(sections[s].sectname)) == 0) {
                    memset((void *)(sections[s].addr + slide), 0, (size_t)sections[s].size);
                }
            }
        }
        command = (const struct load_command *)((const char *)command + command->cmdsize);
    }
}

// Zeroes the counters of every loaded image.
static void iTermCoverageZeroCounters(void) {
    os_unfair_lock_lock(&sImagesLock);
    for (size_t i = 0; i < sImageCount; i++) {
        iTermCoverageZeroImage(sImages[i].header, sImages[i].slide);
    }
    os_unfair_lock_unlock(&sImagesLock);
}

// A file name for a test class.
static NSString *iTermCoverageSafeName(NSString *name) {
    NSCharacterSet *unsafe = [[NSCharacterSet characterSetWithCharactersInString:
                               @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-"] invertedSet];
    return [[name componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
}

- (void)copyProfilesTo:(NSString *)name {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dest = [_outputDirectory stringByAppendingPathComponent:iTermCoverageSafeName(name)];
    [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSString *file in [fm contentsOfDirectoryAtPath:_profileDirectory error:nil]) {
        if (![file hasPrefix:_profilePrefix] || ![file hasSuffix:@".profraw"]) {
            continue;
        }
        NSString *target = [dest stringByAppendingPathComponent:file];
        [fm removeItemAtPath:target error:nil];
        NSError *error = nil;
        if (![fm copyItemAtPath:[_profileDirectory stringByAppendingPathComponent:file]
                         toPath:target
                          error:&error]) {
            NSLog(@"iTermCoveragePerClassObserver: cannot copy %@: %@", file, error);
        }
    }
}

// A suite whose tests are test cases (not suites) is a test class.
static BOOL iTermCoverageIsClassSuite(XCTestSuite *suite) {
    XCTest *first = suite.tests.firstObject;
    return first != nil && ![first isKindOfClass:[XCTestSuite class]];
}

- (void)testSuiteWillStart:(XCTestSuite *)testSuite {
    if (!iTermCoverageIsClassSuite(testSuite)) {
        return;
    }
    if (!_launchSaved) {
        _launchSaved = YES;
        [self copyProfilesTo:@"_launch"];
    }
    iTermCoverageZeroCounters();
}

- (void)testSuiteDidFinish:(XCTestSuite *)testSuite {
    if (!iTermCoverageIsClassSuite(testSuite)) {
        return;
    }
    [self copyProfilesTo:testSuite.name];
    iTermCoverageZeroCounters();
}

@end

// Shows that the observer is inert in an ordinary run.
@interface iTermCoveragePerClassObserverTests : XCTestCase
@end

@implementation iTermCoveragePerClassObserverTests

- (void)testNotRegisteredWithoutTheEnvironmentVariable {
    if (NSProcessInfo.processInfo.environment[iTermCoveragePerClassDirectoryKey].length > 0) {
        XCTSkip(@"This run sets ITERM2_COVERAGE_PER_CLASS_DIR (coverage_tests.sh --observer)");
    }
    XCTAssertFalse([iTermCoveragePerClassObserver isRegistered]);
}

// Dictionary literals are built outside the assertion macros, whose
// arguments cannot contain the literals' commas.
- (nullable NSString *)directoryFor:(NSDictionary<NSString *, NSString *> *)environment {
    return [iTermCoveragePerClassObserver outputDirectoryForEnvironment:environment];
}

- (void)testInertWithoutDirectory {
    NSDictionary<NSString *, NSString *> *empty = @{};
    XCTAssertNil([self directoryFor:empty]);
    NSDictionary<NSString *, NSString *> *profileOnly = @{ @"LLVM_PROFILE_FILE": @"/tmp/x/%c%p-%m.profraw" };
    XCTAssertNil([self directoryFor:profileOnly]);
}

- (void)testInertWithoutContinuousModeOrProcessID {
    NSDictionary<NSString *, NSString *> *noProfile = @{ iTermCoveragePerClassDirectoryKey: @"/tmp/x" };
    XCTAssertNil([self directoryFor:noProfile]);
    NSDictionary<NSString *, NSString *> *noContinuous = @{ iTermCoveragePerClassDirectoryKey: @"/tmp/x",
                                                            @"LLVM_PROFILE_FILE": @"/tmp/x/%p-%m.profraw" };
    XCTAssertNil([self directoryFor:noContinuous]);
    NSDictionary<NSString *, NSString *> *noPID = @{ iTermCoveragePerClassDirectoryKey: @"/tmp/x",
                                                     @"LLVM_PROFILE_FILE": @"/tmp/x/%c%m.profraw" };
    XCTAssertNil([self directoryFor:noPID]);
}

- (void)testActiveWithBoth {
    NSDictionary<NSString *, NSString *> *both = @{ iTermCoveragePerClassDirectoryKey: @"/tmp/x",
                                                    @"LLVM_PROFILE_FILE": @"/tmp/y/%c%p-%m.profraw" };
    XCTAssertEqualObjects([self directoryFor:both], @"/tmp/x");
}

@end

NS_ASSUME_NONNULL_END
