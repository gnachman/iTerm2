//
//  NSURL.m
//  iTerm2
//
//  Created by George Nachman on 4/24/16.
//
//

#import "NSURL+iTerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSURL(iTerm)

- (NSURL *)URLByRemovingFragment {
    if (self.fragment) {
        NSString *string = self.absoluteString;
        NSRange range = [string rangeOfString:@"#"];
        if (range.location != NSNotFound) {
            NSString *stringWithoutFragment = [string substringToIndex:range.location];
            return [NSURL URLWithString:stringWithoutFragment];
        }
    }
    return self;
}

- (NSURL *)URLByAppendingQueryParameter:(NSString *)queryParameter {
    if (!queryParameter.length) {
        return self;
    }

    NSURL *urlWithoutFragment = [self URLByRemovingFragment];
    NSString *fragment;
    if (self.fragment) {
        fragment = [@"#" stringByAppendingString:self.fragment];
    } else {
        fragment = @"";
    }

    NSString *separator;
    if (self.query) {
        if (self.query.length > 0) {
            separator = @"&";
        } else {
            separator = @"";
        }
    } else {
        separator = @"?";
    }

    NSArray *components = @[ urlWithoutFragment.absoluteString, separator, queryParameter, fragment ];
    NSString *string = [components componentsJoinedByString:@""];

    return [NSURL URLWithString:string];
}

+ (NSURL *)URLWithUserSuppliedString:(NSString *)string {
    NSCharacterSet *nonAsciiCharacterSet = [NSCharacterSet characterSetWithRange:NSMakeRange(128, 0x10FFFF - 128)];
    if ([string rangeOfCharacterFromSet:nonAsciiCharacterSet].location != NSNotFound) {
        NSUInteger fragmentIndex = [string rangeOfString:@"#"].location;
        if (fragmentIndex != NSNotFound) {
            // Don't want to percent encode a #.
            NSString *before = [[string substringToIndex:fragmentIndex] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            NSString *after = [[string substringFromIndex:fragmentIndex + 1] stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
            NSString *combined = [NSString stringWithFormat:@"%@#%@", before, after];
            return [NSURL URLWithString:combined];
        } else {
            return [NSURL URLWithString:[string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]]];
        }
    } else {
        return [NSURL URLWithString:string];
    }
}

- (nullable NSData *)zippedContents {
    if (!self.fileURL) {
        return nil;
    }

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSURL *destination =
        [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:uuid];

    BOOL ok = [self saveContentsOfPathToZip:destination];
    if (ok) {
        NSData *data = [NSData dataWithContentsOfURL:destination];
        [[NSFileManager defaultManager] removeItemAtURL:destination error:NULL];
        return data;
    } else {
        return nil;
    }
}

- (BOOL)saveContentsOfPathToZip:(NSURL *)destination {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    BOOL isDir = NO;
    if (![fileManager fileExistsAtPath:self.path isDirectory:&isDir]) {
        return NO;
    }

    NSURL *sourceDir = nil;
    BOOL sourceDirIsTemporary= NO;
    if (isDir) {
        sourceDir = self;
        sourceDirIsTemporary = NO;
    } else {
        NSString *uuid = [[NSUUID UUID] UUIDString];
        sourceDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:uuid];

        NSError *error;
        [fileManager createDirectoryAtURL:sourceDir
              withIntermediateDirectories:YES
                               attributes:nil
                                    error:&error];
        if (error) {
            return NO;
        }
        NSURL *tempURL = [sourceDir URLByAppendingPathComponent:self.lastPathComponent ?: @"file"];

        [fileManager copyItemAtURL:self toURL:tempURL error:&error];
        if (error) {
            return NO;
        }

        sourceDirIsTemporary = YES;
    }

    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] init];
    __block NSError *error = nil;
    [coordinator coordinateReadingItemAtURL:sourceDir
                                    options:NSFileCoordinatorReadingForUploading
                                      error:&error
                                 byAccessor:^(NSURL * _Nonnull zippedURL) {
                                     [fileManager copyItemAtURL:zippedURL
                                                          toURL:destination
                                                          error:&error];
                                 }];
    if (sourceDirIsTemporary) {
        [fileManager removeItemAtURL:sourceDir error:NULL];
    }
    return YES;
}

@end

NS_ASSUME_NONNULL_END
