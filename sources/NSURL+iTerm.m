//
//  NSURL.m
//  iTerm2
//
//  Created by George Nachman on 4/24/16.
//
//

#import "NSURL+iTerm.h"

#import "DebugLogging.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+IDN.h"

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

// This takes a string that has a combination of well-encoded characters and totally
// illegal-in-a-URL characters, and turns it into a proper URL.
//
// Nobody wants to write code to parse a URL. So we don't!
//
// This algorithm replaces any sequence of characters that aren't part of the structure of a URL and
// replaces them with a nice safe ASCII string, mostly numbers. So for example:
//
//   https://user:password@example.com:8080/path/to/file?query=value&query=value#fragment
//
// Gets turned in to:
//
//   x12://11@10:9/8/7/6?5=4&3=2#1
//
// If what the user gave is us is roughly URL shaped this can be turned in to NSURLComponents.
// It appears to have a competent URL parser, but it does want reasonably well-formed input.
//
// Then we replace each component with its original value. So x12 -> https, 11 -> user, etc.
//
// Note that NSURLComponents likes its values to be unencoded, so it can have all the crazy stuff
// the user gave us and it can (mostly) turn it in to a URL.
//
// The reason there was a mostly is because it doesn't know about IDN. So we IDN-encode the
// hostname before generating a URL.
+ (NSURL *)URLWithUserSuppliedString:(NSString *)string {
    DLog(@"Trying to make a proper URL out of: %@", string);

    // Convert all sequences of non-reserved symbols into numbers 0, 1, 2, ...
    NSCharacterSet *reservedSymbols = [NSCharacterSet characterSetWithCharactersInString:@":/@:.#?&="];
    NSIndexSet *nonReservedSymbolIndices = [string indicesOfCharactersInSet:[reservedSymbols invertedSet]];
    __block int count = 0x10000000;
    NSMutableString *stringWithPlaceholders = [string mutableCopy];
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    [nonReservedSymbolIndices enumerateRangesWithOptions:NSEnumerationReverse
                                              usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
        NSString *placeholder = [NSString stringWithFormat:@"%08x", count++];
        if (range.location == 0) {
            // Schemes can't start with a number. In case the first thing is a scheme, start it
            // with a letter. This is safe because ports are the only thing that must be a number
            // but they can't come first!
            placeholder = [@"x" stringByAppendingString:placeholder];
        }
        [stringWithPlaceholders replaceCharactersInRange:range withString:placeholder];
        // We have to remove percent encoding here or it gets double-encoded. If there is a percent
        // that is not part of a percent encoding scheme, then -stringByRemovingPercentEncoding
        // will return nil and then we just use the raw string. A mix of percent-encoded and
        // non-percent-encoded will not work, nor will non-percent-encoded that happens to look like
        // percent-encoded.
        NSString *substring = [string substringWithRange:range];
        map[placeholder] = [substring stringByRemovingPercentEncoding] ?: substring;
    }];
    DLog(@"stringWithPlaceholders=%@", stringWithPlaceholders);
    DLog(@"map=%@", map);

    NSURLComponents *components = [NSURLComponents componentsWithString:stringWithPlaceholders];
    DLog(@"components=%@", components);

    NSString *(^glue)(NSString *) = ^NSString *(NSString *encoded) {
        NSMutableString *result = [encoded mutableCopy];
        [map enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL * _Nonnull stop) {
            const NSRange range = [result rangeOfString:key];
            if (range.location == NSNotFound) {
                return;
            }
            [result replaceCharactersInRange:range withString:obj];
        }];
        return result;
    };
    if (components.scheme) {
        @try {
            components.scheme = glue(components.scheme);
        } @catch (NSException *exception) {
            return nil;
        }
    }
    if (components.user) {
        components.user = glue(components.user);
    }
    if (components.password) {
        components.password = glue(components.password);
    }
    if (components.host) {
        components.host = [NSURL IDNEncodedHostname:glue(components.host)];
    }
    if (components.port) {
        @try {
            components.port = @([glue(components.port.stringValue) integerValue]);
        } @catch (NSException *exception) {
            return nil;
        }
    }
    if (components.path) {
        components.path = glue(components.path);
    }
    if (components.fragment) {
        components.fragment = glue(components.fragment);
    }
    if (components.queryItems.count) {
        components.queryItems = [components.queryItems mapWithBlock:^id(NSURLQueryItem *item) {
            return [NSURLQueryItem queryItemWithName:glue(item.name) ?: @""
                                               value:glue(item.value)];
        }];
    }
    DLog(@"Final result: %@", components.URL);
    return components.URL;
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
