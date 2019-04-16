//
//  iTermPathFinder.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import "iTermPathFinder.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermPathCleaner.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

static dispatch_queue_t iTermPathFinderQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.iterm2.path-finder", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@interface iTermPathFinder()
@property (atomic) BOOL canceled;
@end

@implementation iTermPathFinder {
    NSString *_beforeStringIn;
    NSString *_afterStringIn;
    NSString *_workingDirectory;
    BOOL _trimWhitespace;
}

- (instancetype)initWithPrefix:(NSString *)beforeStringIn
                        suffix:(NSString *)afterStringIn
              workingDirectory:(NSString *)workingDirectory
                trimWhitespace:(BOOL)trimWhitespace {
    self = [super init];
    if (self) {
        _beforeStringIn = [beforeStringIn copy];
        _afterStringIn = [afterStringIn copy];
        _workingDirectory = [workingDirectory copy];
        _trimWhitespace = trimWhitespace;
        _fileManager = [NSFileManager defaultManager];
    }
    return self;
}

- (void)cancel {
    self.canceled = YES;
}

- (void)searchWithCompletion:(void (^)(void))completion {
    dispatch_async(iTermPathFinderQueue(), ^{
        [self searchSynchronously];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion();
        });
    });
}

- (void)searchSynchronously {
    BOOL workingDirectoryIsOk = [self fileExistsAtPathLocally:_workingDirectory];
    if (!workingDirectoryIsOk) {
        DLog(@"Working directory %@ is a network share or doesn't exist. Not using it for context.",
             _workingDirectory);
    }

    DLog(@"Brute force path from prefix <<%@>>, suffix <<%@>> directory=%@",
         _beforeStringIn, _afterStringIn, _workingDirectory);

    // Split "Foo Bar" to ["Foo", " ", "Bar"]
    NSArray *beforeChunks = [self splitString:_beforeStringIn];
    NSArray *afterChunks = [self splitString:_afterStringIn];

    NSMutableString *left = [NSMutableString string];
    int iterationsBeforeQuitting = 100;  // Bail after 100 iterations if nothing is still found.
    NSMutableSet *paths = [NSMutableSet set];
    NSCharacterSet *whitespaceCharset = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (int i = [beforeChunks count]; i >= 0; i--) {
        if (self.canceled) {
            _path = nil;
            return;
        }
        NSString *beforeChunk = @"";
        if (i < [beforeChunks count]) {
            beforeChunk = beforeChunks[i];
        }

        [left insertString:beforeChunk atIndex:0];
        NSMutableString *right = [NSMutableString string];
        // Do not search more than 10 chunks forward to avoid starving leftward search.
        for (int j = 0; j < MAX(1, afterChunks.count) && j < 10; j++) {
            if (self.canceled) {
                _path = nil;
                return;
            }
            NSString *rightChunk = @"";
            if (j < afterChunks.count) {
                rightChunk = afterChunks[j];
            }
            [right appendString:rightChunk];

            NSString *possiblePath = [left stringByAppendingString:right];
            NSString *trimmedPath = possiblePath;
            if (_trimWhitespace) {
                trimmedPath = [trimmedPath stringByTrimmingCharactersInSet:whitespaceCharset];
            }
            if ([paths containsObject:[NSString stringWithString:trimmedPath]]) {
                continue;
            }
            [paths addObject:[trimmedPath copy]];

            // Replace \x with x for x in: space, (, [, ], \, ).
            NSString *removeEscapingSlashes = @"\\\\([ \\(\\[\\]\\\\)])";
            trimmedPath = [trimmedPath stringByReplacingOccurrencesOfRegex:removeEscapingSlashes withString:@"$1"];

            // Some programs will thoughtlessly print a filename followed by some silly suffix.
            // We'll try versions with and without a questionable suffix. The version
            // with the suffix is always preferred if it exists.
            static NSArray *questionableSuffixes;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
                questionableSuffixes = @[ @"!", @"?", @".", @",", @";", @":", @"...", @"…" ];
            });
            for (NSString *modifiedPossiblePath in [self pathsFromPath:trimmedPath byRemovingBadSuffixes:questionableSuffixes]) {
                if (self.canceled) {
                    _path = nil;
                    return;
                }
                BOOL exists = NO;
                if (workingDirectoryIsOk || [modifiedPossiblePath hasPrefix:@"/"]) {
                    iTermPathCleaner *cleaner = [[iTermPathCleaner alloc] initWithPath:modifiedPossiblePath
                                                                                suffix:nil
                                                                      workingDirectory:_workingDirectory];
                    cleaner.fileManager = self.fileManager;
                    [cleaner cleanSynchronously];
                    exists = (cleaner.cleanPath != nil);
                }
                if (exists) {
                    NSString *extra = @"";
                    if (j + 1 < afterChunks.count) {
                        extra = [self columnAndLineNumberFromChunks:[afterChunks subarrayFromIndex:j + 1]];
                    }
                    NSString *extendedPath = [modifiedPossiblePath stringByAppendingString:extra];
                    [right appendString:extra];

                    if (_trimWhitespace &&
                        [[right stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length] == 0) {
                        // trimmedPath is trim(left + right). If trim(right) is empty
                        // then we don't want to count trailing whitespace from left in the chars
                        // taken from prefix.
                        _prefixChars = [[left stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length];
                    } else {
                        _prefixChars = left.length;
                    }
                    NSInteger lengthOfBadSuffix = extra.length ? 0 : trimmedPath.length - modifiedPossiblePath.length;
                    int n;
                    if (_trimWhitespace) {
                        n = [[right stringByTrimmingTrailingCharactersFromCharacterSet:whitespaceCharset] length] - lengthOfBadSuffix;
                    } else {
                        n = right.length - lengthOfBadSuffix;
                    }
                    _suffixChars = MAX(0, n);
                    DLog(@"Using path %@", extendedPath);
                    _path = [extendedPath copy];
                    return;
                }
            }
            if (--iterationsBeforeQuitting == 0) {
                _path = nil;
                return;
            }
        }
    }
    _path = nil;
    return;
}

#pragma mark - Private

#pragma mark Filesystem

- (BOOL)fileExistsAtPathLocally:(NSString *)path {
    return [self.fileManager fileExistsAtPathLocally:path
                              additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

- (BOOL)fileHasForbiddenPrefix:(NSString *)path {
    return [self.fileManager fileHasForbiddenPrefix:path
                             additionalNetworkPaths:[[iTermAdvancedSettingsModel pathsToIgnore] componentsSeparatedByString:@","]];
}

#pragma mark String Manipulation

- (NSArray<NSString *> *)splitString:(NSString *)string {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    __block NSRange lastRange = NSMakeRange(0, 0);
    [string enumerateStringsMatchedByRegex:@"([^\t ():]*)([\t ():])"
                                   options:0
                                   inRange:NSMakeRange(0, string.length)
                                     error:nil
                        enumerationOptions:0
                                usingBlock:^(NSInteger captureCount,
                                             NSString *const __unsafe_unretained *capturedStrings,
                                             const NSRange *capturedRanges,
                                             volatile BOOL *const stop) {
                                    [parts addObject:capturedStrings[1]];
                                    [parts addObject:capturedStrings[2]];
                                    lastRange = capturedRanges[2];
                                }];
    const NSInteger suffixStartIndex = NSMaxRange(lastRange);
    if (suffixStartIndex < string.length) {
        [parts addObject:[string substringFromIndex:suffixStartIndex]];
    }
    return parts;
}

- (NSArray *)pathsFromPath:(NSString *)source byRemovingBadSuffixes:(NSArray *)badSuffixes {
    NSMutableArray *result = [NSMutableArray array];
    [result addObject:source];
    for (NSString *badSuffix in badSuffixes) {
        if ([source hasSuffix:badSuffix]) {
            NSString *stripped = [source substringToIndex:source.length - badSuffix.length];
            if (stripped.length) {
                [result addObject:stripped];
            }
        }
    }
    return result;
}

#pragma mark - Line Numbers

- (NSString *)columnAndLineNumberFromChunks:(NSArray<NSString *> *)afterChunks {
    NSString *suffix = [afterChunks componentsJoinedByString:@""];
    NSArray<NSString *> *regexes = @[ @"^(:\\d+:\\d+)",
                                      @"^(:\\d+)",
                                      @"^(\\[\\d+, ?\\d+])",
                                      @"^(\", line \\d+, column \\d+)",
                                      @"^(\\(\\d+, ?\\d+\\))"];
    for (NSString *regex in regexes) {
        NSString *value = [suffix stringByMatching:regex capture:1];
        if (value) {
            return value;
        }
    }
    return @"";
}

@end
