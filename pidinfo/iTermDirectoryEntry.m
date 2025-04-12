//
//  iTermDirectoryEntry.m
//  iTerm2
//
//  Created by George Nachman on 4/12/25.
//

#import "iTermDirectoryEntry.h"

@implementation iTermDirectoryEntry
- (instancetype)initWithName:(NSString *)name statBuf:(struct stat)sb {
    self = [super init];
    if (self) {
        _name = [name copy];
        _mode = sb.st_mode;
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name mode:(mode_t)mode {
    struct stat sb = { 0 };
    sb.st_mode = mode;
    return [self initWithName:name statBuf:sb];
}

- (BOOL)isDirectory {
    return (_mode & S_IFMT) == S_IFDIR;
}

- (BOOL)isReadable {
    return (_mode & (S_IRUSR | S_IRGRP | S_IROTH)) != 0;
}

- (BOOL)isExecutable {
    return (_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0;
}

#pragma mark - NSSecureCoding

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeInteger:self.mode forKey:@"mode"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    NSString *name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
    NSUInteger mode = [coder decodeIntegerForKey:@"mode"];

    struct stat sb = {0};
    sb.st_mode = mode;
    return [self initWithName:name statBuf:sb];
}

@end
