//
//  iTermPathCleaner.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "iTermPathCleaner.h"

#import "DebugLogging.h"
#import "NSArray+CommonAdditions.h"
#import "NSFileManager+CommonAdditions.h"
#import "NSString+CommonAdditions.h"
#import "RegexKitLite.h"

static dispatch_queue_t iTermPathCleanerQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.path-cleaner", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface iTermPathCleaner ()
@property (atomic, readwrite) NSString *cleanPath;
@property (nullable, atomic, readwrite) NSString *lineNumber;
@property (nullable, atomic, readwrite) NSString *columnNumber;
@end

@implementation iTermPathCleaner {
    NSString *_path;
    NSString *_suffix;
    NSString *_workingDirectory;
    NSArray<NSString *> *_pathsToIgnore;
    BOOL _allowNetworkMounts;
}

- (instancetype)initWithPath:(NSString *)path
                      suffix:(NSString *)suffix
            workingDirectory:(NSString *)workingDirectory
                      ignore:(NSString *)pathsToIgnore
          allowNetworkMounts:(BOOL)allowNetworkMounts {
    self = [super init];
    if (self) {
        _path = [path copy];
        _suffix = [suffix copy];
        _workingDirectory = [workingDirectory copy];
        _fileManager = [NSFileManager defaultManager];
        _pathsToIgnore = [pathsToIgnore componentsSeparatedByString:@","];
        _allowNetworkMounts = allowNetworkMounts;
    }
    return self;
}

- (void)cleanWithCompletion:(void (^)(void))completion {
    dispatch_async(iTermPathCleanerQueue(), ^{
        [self cleanSynchronously];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

- (NSString *)pathByRemovingDiffPrefix:(NSString *)path {
    if (![path hasPrefix:@"a/"] && ![path hasPrefix:@"b/"]) {
        return nil;
    }
    return [path substringFromIndex:2];
}

- (void)cleanSynchronously {
    self.lineNumber = nil;
    self.columnNumber = nil;
    self.cleanPath = [self reallyCleanSynchronously:_path];
}

- (NSString *)reallyCleanSynchronously:(NSString *)path {
    NSString *stringToSearchForLineAndColumn = _suffix;
    NSString *pathWithoutNearbyGunk = [self pathByStrippingEnclosingPunctuationFromPath:path
                                                                     lineAndColumnMatch:&stringToSearchForLineAndColumn];
    if (!pathWithoutNearbyGunk) {
        return nil;
    }
    if (stringToSearchForLineAndColumn) {
        [self extractFromSuffix:stringToSearchForLineAndColumn];
    }
    NSString *fullPath = [self getFullPath:pathWithoutNearbyGunk workingDirectory:_workingDirectory];
    if (fullPath) {
        return fullPath;
    }

    // If path doesn't exist and it starts with "a/" or "b/" (from `diff`), try again without the
    // [ab]/ prefix.
    pathWithoutNearbyGunk = [self pathByRemovingDiffPrefix:pathWithoutNearbyGunk];
    if (!pathWithoutNearbyGunk) {
        return nil;
    }

    // Repeat the cleanup.
    DLog(@"[%d]  Treating as diff path", _reqid);
    return [self getFullPath:pathWithoutNearbyGunk workingDirectory:_workingDirectory];
}

- (NSString *)getFullPath:(NSString *)pathExLineNumberAndColumn
         workingDirectory:(NSString *)workingDirectory {
    DLog(@"[%d] Check if %@ is a valid path in %@", _reqid, pathExLineNumberAndColumn, workingDirectory);
    // TODO(chendo): Move regex, define capture semantics in config file/prefs
    if (!pathExLineNumberAndColumn || [pathExLineNumberAndColumn length] == 0) {
        DLog(@"[%d]  no: it is empty", _reqid);
        return nil;
    }

    NSString *path = [pathExLineNumberAndColumn stringByExpandingTildeInPath];
    DLog(@"[%d]  Strip line number suffix leaving %@", _reqid, path);
    if ([path length] == 0) {
        // Everything was stripped out, meaning we'd try to open the working directory.
        return nil;
    }
    if (![path hasPrefix:@"/"]) {
        path = [workingDirectory stringByAppendingPathComponent:path];
        DLog(@"[%d]  Prepend working directory, giving %@", _reqid, path);
    }

    // NOTE: The path used to be standardized first. While that would allow us to catch
    // network paths, it also caused filesystem access that would hit network paths.
    // That was also true for fileURLWithPath:.
    DLog(@"[%d]    Check path for forbidden prefix %@", _reqid, path);
    if ([self fileHasForbiddenPrefix:path]) {
        DLog(@"[%d]    NO: Path has forbidden prefix.", _reqid);
        return nil;
    }


    DLog(@"[%d]  Checking if file exists locally: %@", _reqid, path);
    if ([self fileExistsAtPathLocally:path]) {
        DLog(@"[%d]    YES: A file exists at %@", _reqid, path);
        NSURL *url = [NSURL fileURLWithPath:path];

        // Resolve path by removing ./ and ../ etc
        path = [[url standardizedURL] path];

        return path;
    }
    DLog(@"[%d]     NO: no valid path found", _reqid);
    return nil;
}

- (void)extractFromSuffix:(NSString *)suffix {
    NSArray<NSString *> *regexes = [[self lineAndColumnNumberRegexes] mapWithBlock:^id(NSString *anObject) {
        return [@"^" stringByAppendingString:anObject];
    }];
    for (NSString *regex in regexes) {
        NSString *match = [suffix stringByMatching:regex];
        if (!match) {
            continue;
        }
        const NSInteger matchLength = match.length;
        if (matchLength < suffix.length) {
            // If part of `suffix` would remain, we can't use it.
            continue;
        }
        DLog(@"[%d]  Suffix of %@ matches regex %@", _reqid, suffix, regex);
        NSArray<NSArray<NSString *> *> *matches = [suffix arrayOfCaptureComponentsMatchedByRegex:regex];
        NSArray<NSString *> *captures = matches.firstObject;
        if (captures.count > 1) {
            self.lineNumber = captures[1];
        }
        if (captures.count > 2) {
            self.columnNumber = captures[2];
        }
        return;
    }
}

#pragma mark - Column/Line Number

// The input starts with the filename. Removing the matched range should leave behind just the filename. Trailing punctuation will be removed from the input before matching. See call site for how the input is mangled.
- (NSArray<NSString *> *)lineAndColumnNumberRegexes {
    return @[ @":(\\d+):(\\d+)",
              @":(\\d+)",
              @"\\[(\\d+), ?(\\d+)]",
              @"\", line (\\d+), column (\\d+)",
              @"\", line (\\d+), in",
              @"\\((\\d+), ?(\\d+)\\)",
              @"\\((\\d+)\\)",
              @" line (\\d+)$"];
    // NOTE: If you change this also update regexes in iTermPathFinder.
}

- (NSString *)pathByStrippingEnclosingPunctuationFromPath:(NSString *)path
                                       lineAndColumnMatch:(NSString **)lineAndColumnMatch {
    if (!path || [path length] == 0) {
        DLog(@"[%d]  no: it is empty", _reqid);
        return nil;
    }

    // If it's in any form of bracketed delimiters, strip them
    path = [path stringByRemovingEnclosingBrackets];

    // Strip various trailing characters that are unlikely to be part of the file name.
    NSString *trailingPunctuationRegex = @"[.,:]$";
    path = [path stringByReplacingOccurrencesOfRegex:trailingPunctuationRegex
                                          withString:@""];

    // Try to chop off a trailing line/column number.
    NSArray<NSString *> *regexes = [self.lineAndColumnNumberRegexes mapWithBlock:^id(NSString *anObject) {
        return [anObject stringByAppendingString:@"$"];
    }];
    for (NSString *regex in regexes) {
        NSString *match = [path stringByMatching:regex];
        if (!match) {
            continue;
        }
        if (lineAndColumnMatch) {
            *lineAndColumnMatch = match;
        }
        return [path stringByDroppingLastCharacters:match.length];
    }

    // No trailing line/column number. Drop a trailing paren.
    if ([path hasSuffix:@")"]) {
        return [path stringByDroppingLastCharacters:1];
    }

    return path;
}

#pragma mark Filesystem

- (BOOL)fileExistsAtPathLocally:(NSString *)path {
    return [self.fileManager fileExistsAtPathLocally:path
                              additionalNetworkPaths:_pathsToIgnore
                                  allowNetworkMounts:_allowNetworkMounts];
}

- (BOOL)fileHasForbiddenPrefix:(NSString *)path {
    return [self.fileManager fileHasForbiddenPrefix:path
                             additionalNetworkPaths:_pathsToIgnore];
}

@end
