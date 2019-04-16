//
//  iTermPathCleaner.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/15/19.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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
