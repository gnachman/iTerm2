//
//  iTermPathCleaner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Takes a string containing a path to a file, plus the string that follows the filename, and tries
// to improve it:
// - Remove enclosing brackets, turning <([foo])> into foo
// - Remove trailing punctuation, turning foo. into foo
// - Remove trailing line & column number, turning foo:1:2 into foo
// - Remove trailing unbalanced parenthesis, turning foo) into foo
// - Expand leading tilde
// - Make the path absolute relative to the provided working directory
// - Check if it appears to be on a network mount, failing if so.
// - Ensure the file actually exists; if it does not, try again by removing an a/ or b/ prefix
//   (as seen in diff output)
// - Standardize the path by removing . and .. anywhere in the path,
//   turning /bar/baz/../foo into /bar/foo
//
// Furthermore, the line and column number are extracted from either the suffix or the path after
// removing enclosing punctuation, wherever they may appear.
//
// tl;dr: Given a mess like "(a/bar/baz/../foo:1:2)." convert it to $PWD/bar/foo and extracts the
// line and column number into properties, or returns nil if $PWD/bar/foo does not exist.
@interface iTermPathCleaner : NSObject

@property (atomic, readonly) NSString *cleanPath;
@property (nullable, atomic, readonly) NSString *lineNumber;
@property (nullable, atomic, readonly) NSString *columnNumber;
@property (nonatomic, strong) NSFileManager *fileManager;

- (instancetype)initWithPath:(NSString *)path
                      suffix:(nullable NSString *)suffix
            workingDirectory:(NSString *)workingDirectory NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

- (void)cleanSynchronously;
- (void)cleanWithCompletion:(void (^)(void))completion;

@end

NS_ASSUME_NONNULL_END
