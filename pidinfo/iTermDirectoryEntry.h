//
//  iTermDirectoryEntry.h
//  iTerm2
//
//  Created by George Nachman on 4/12/25.
//

#import <Foundation/Foundation.h>
#include <sys/stat.h>

NS_ASSUME_NONNULL_BEGIN

@interface iTermDirectoryEntry: NSObject<NSSecureCoding>

@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) mode_t mode;

@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic, readonly) BOOL isReadable;
@property (nonatomic, readonly) BOOL isExecutable;

- (instancetype)initWithName:(NSString *)name statBuf:(struct stat)sb NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithName:(NSString *)name mode:(mode_t)mode;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
