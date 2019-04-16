//
//  iTermPathFinder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Given two strings "before" and "after" try to find a filename by searching outward from their
// concatenation.
//
// The strings are split on various separators like whitespace, tabs, and parens. Chunks are
// combined to form possible file names. Escaping backslashes are removed. Trailing punctuation
// is removed. If the file exists, the path is cleaned up (see iTermPathCleaner) to extract a
// possible line number and column number from it, trim whitespace (if requested), and return the
// path of an *existing* file.
//
@interface iTermPathFinder : NSObject

// How many characters were used from the prefix or suffix? Used to find the range to underline.
@property (nonatomic, readonly) int prefixChars;
@property (nonatomic, readonly) int suffixChars;
@property (nullable, nonatomic, readonly) NSString *path;
@property (nonatomic, strong) NSFileManager *fileManager;

- (instancetype)initWithPrefix:(NSString *)beforeStringIn
                        suffix:(NSString *)afterStringIn
              workingDirectory:(NSString *)workingDirectory
                trimWhitespace:(BOOL)trimWhitespace NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)searchSynchronously;
- (void)searchWithCompletion:(void (^)(void))completion;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
