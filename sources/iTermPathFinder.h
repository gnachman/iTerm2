//
//  iTermPathFinder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermPathFinder : NSObject

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
