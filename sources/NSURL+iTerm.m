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

    // First try the simple, stupid thing for well-formed URLs.
    NSURL *url = [NSURL URLWithString:string];
    if (url) {
        DLog(@"Seems legit to me. %@", url.absoluteString);
        return url;
    }

    // Simple and stupid didn't work. Try complicated and stupid.
    return [self URLWithUserSuppliedStringImpl:string];
}

+ (NSURL *)URLWithUserSuppliedStringImpl:(NSString *)string {
    // Convert all sequences of non-reserved symbols into numbers 0, 1, 2, ...
    NSCharacterSet *reservedSymbols = [NSCharacterSet characterSetWithCharactersInString:@":/@.#?&="];
    NSMutableIndexSet *nonReservedSymbolIndices = [[string indicesOfCharactersInSet:[reservedSymbols invertedSet]] mutableCopy];
    // Remove any colons that occur after the first [ to avoid picking up colons in IPv6 addresses
    // while preserving any in user:password@ and scheme:
    const NSRange rangeOfFirstOpenSquareBracket = [string rangeOfString:@"["];
    if (rangeOfFirstOpenSquareBracket.location != NSNotFound) {
        [[string indicesOfCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":"]] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
            if (idx > NSMaxRange(rangeOfFirstOpenSquareBracket)) {
                [nonReservedSymbolIndices addIndex:idx];
            }
        }];
    }

    __block int count = 0x10000000;
    NSMutableString *stringWithPlaceholders = [string mutableCopy];
    NSMutableDictionary<NSString *, NSString *> *map = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *originalValuesMap = [NSMutableDictionary dictionary];
    [nonReservedSymbolIndices enumerateRangesWithOptions:NSEnumerationReverse
                                              usingBlock:^(NSRange range, BOOL * _Nonnull stop) {
        NSString *placeholder = [NSString stringWithFormat:@"%08d", count++];
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
        originalValuesMap[placeholder] = substring;
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
    NSString *(^glueOriginal)(NSString *) = ^NSString *(NSString *encoded) {
        NSMutableString *result = [encoded mutableCopy];
        [originalValuesMap enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull key, NSString *_Nonnull obj, BOOL * _Nonnull stop) {
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
        if (components.port) {
            components.host = [NSURL IDNEncodedHostname:glue(components.host)];
        } else {
            NSString *compositeString = glue(components.host);
            NSRange rangeOfLastColon = [compositeString rangeOfString:@":" options:NSBackwardsSearch];
            // See note above about IPv6 making ports & user/pw complicated.
            if (rangeOfLastColon.location == NSNotFound) {
                components.host = [NSURL IDNEncodedHostname:compositeString];
            } else {
                NSString *possiblePort = [compositeString substringFromIndex:NSMaxRange(rangeOfLastColon)];
                if ([possiblePort isNumeric]) {
                    components.port = @(possiblePort.iterm_unsignedIntegerValue);
                    components.host = [NSURL IDNEncodedHostname:[compositeString substringToIndex:rangeOfLastColon.location]];
                } else {
                    components.host = [NSURL IDNEncodedHostname:compositeString];
                }
            }
        }
    }
    if (components.port) {
        @try {
            components.port = @([glue(components.port.stringValue) integerValue]);
        } @catch (NSException *exception) {
            return nil;
        }
    }
    NSString *semicolonUUID = [[NSUUID UUID] UUIDString];
    if (components.path) {
        NSString *path = glue(components.path);
        // Temporarily replace semicolons with a UUID. This lets us build NSURLComponents with no
        // semicolons in the path and the resulting URLString will not have encoded
        // semicolons (%3B). It is not necessary to encode them as semis are legal in paths.
        // In the future more punctuation could be treated this way. See issue 9598.
        NSArray<NSString *> *parts = [path componentsSeparatedByString:@";"];
        components.path = [parts componentsJoinedByString:semicolonUUID];
    }
    if (components.fragment) {
        components.fragment = glue(components.fragment);
    }
    // Preserve the original query param. Convert each query item to a UUID and then replace it with the original value.
    NSMutableDictionary<NSString *, NSURLQueryItem *> *uuidToQueryItem = [NSMutableDictionary dictionary];
    if (components.queryItems.count) {
        components.queryItems = [components.queryItems mapWithBlock:^id(NSURLQueryItem *item) {
            NSString *uuid = [[NSUUID UUID] UUIDString];
            uuidToQueryItem[uuid] = item;
            return [NSURLQueryItem queryItemWithName:uuid value:nil];
        }];
    }
    NSMutableCharacterSet *charset = [[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy];
    // In Big Sur, the following characters are allowed:
    //   !$&'()*+,-./0123456789:;=?@ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~
    // I want to also allow % in the case that the string is already percent-encoded.
    // The desire is for already-percent-encoded strings to be left alone but strings with stuff like
    // non-ascii letters to be encoded.
    // There is a narrow opening for queries like `fraction=50%` to be left invalid, but I expect
    // that to be much rarer than "the query is already percent encoded" plus "the query is not percent
    // encoded and contains no raw percents".
    [charset addCharactersInString:@"%"];
    NSMutableString *urlString = [components.URL.absoluteString mutableCopy];
    [uuidToQueryItem enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull uuid, NSURLQueryItem * _Nonnull queryItem, BOOL * _Nonnull stop) {
        NSString *queryParam;
        NSString *name = glueOriginal(queryItem.name);
        NSString *value = glueOriginal(queryItem.value);
        if (!name && !value) {
            queryParam = @"";
        } else if (name && !value) {
            queryParam = name;
        } else {
            queryParam = [NSString stringWithFormat:@"%@=%@", name ?: @"", value];
        }
        [urlString replaceOccurrencesOfString:uuid
                                   withString:[queryParam stringByAddingPercentEncodingWithAllowedCharacters:charset]
                                      options:0
                                        range:NSMakeRange(0, urlString.length)];
    }];

    // Restore semicolons in path
    [urlString replaceOccurrencesOfString:semicolonUUID withString:@";" options:0 range:NSMakeRange(0, urlString.length)];

    DLog(@"Final result: %@", urlString);
    return [NSURL URLWithString:urlString];
}

- (nullable NSData *)zippedContents {
    if (!self.fileURL) {
        return nil;
    }

    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSURL *destination =
    [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:[uuid stringByAppendingString:@".zip"]];

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

    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/zip"];

    NSString *destinationPath = [destination path];
    NSString *sourcePath = [sourceDir path];

    [task setArguments:@[@"-r", destinationPath, sourcePath]];

    @try {
        [task launch];
        [task waitUntilExit];
        if (sourceDirIsTemporary) {
            [fileManager removeItemAtURL:sourceDir error:NULL];
        }
        return YES;
    } @catch (NSException *exception) {
        NSLog(@"Failed to create zip file: %@", [exception reason]);
        return NO;
    }
}

@end

NS_ASSUME_NONNULL_END
