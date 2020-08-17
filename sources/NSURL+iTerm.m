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

+ (nullable NSURL *)urlByReplacingFormatSpecifier:(NSString *)formatSpecifier
                                         inString:(NSString *)string
                                        withValue:(NSString *)value {
    if (![string containsString:formatSpecifier]) {
        return [NSURL URLWithString:string];
    }

    NSString *placeholder = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
    NSString *urlString = [string stringByReplacingOccurrencesOfString:formatSpecifier
                                                            withString:placeholder];
    NSURLComponents *components = [[NSURLComponents alloc] initWithString:urlString];

    // Query item value?
    {
        NSMutableArray<NSURLQueryItem *> *queryItems = [components.queryItems mutableCopy];
        const NSUInteger i = [queryItems indexOfObjectPassingTest:^BOOL(NSURLQueryItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.value isEqualToString:placeholder];
        }];
        if (queryItems && i != NSNotFound) {
            queryItems[i] = [NSURLQueryItem queryItemWithName:queryItems[i].name value:value];
            components.queryItems = queryItems;
            return components.URL;
        }
    }

    // Query item name?
    {
        NSMutableArray<NSURLQueryItem *> *queryItems = [components.queryItems mutableCopy];
        const NSUInteger i = [queryItems indexOfObjectPassingTest:^BOOL(NSURLQueryItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            return [obj.name isEqualToString:placeholder];
        }];
        if (queryItems && i != NSNotFound) {
            queryItems[i] = [NSURLQueryItem queryItemWithName:value value:queryItems[i].value];
            components.queryItems = queryItems;
            return components.URL;
        }
    }

    // Fragment?
    {
        const NSRange range = [components.fragment rangeOfString:placeholder];
        if (components.fragment && range.location != NSNotFound) {
            components.fragment = [components.fragment stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    // Path?
    {
        const NSRange range = [components.path rangeOfString:placeholder];
        if (components.path && range.location != NSNotFound) {
            components.path = [components.path stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    // Hostname?
    {
        const NSRange range = [components.host rangeOfString:placeholder];
        if (components.host && range.location != NSNotFound) {
            components.host = [components.host stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    // Scheme?
    {
        const NSRange range = [components.scheme rangeOfString:placeholder];
        if (components.scheme && range.location != NSNotFound) {
            components.scheme = [components.scheme stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    // User name?
    {
        const NSRange range = [components.user rangeOfString:placeholder];
        if (components.user && range.location != NSNotFound) {
            components.user = [components.user stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    // Password?
    {
        const NSRange range = [components.password rangeOfString:placeholder];
        if (components.password && range.location != NSNotFound) {
            components.password = [components.password stringByReplacingCharactersInRange:range withString:value];
            return components.URL;
        }
    }

    return nil;
}

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
