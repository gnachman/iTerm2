//
//  iTermSetupPyParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermSetupPyParser.h"

#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "RegexKitLite.h"

@implementation iTermSetupPyParser {
    NSArray<NSString *> *_dependencies;
}

+ (void)writeSetupPyToFile:(NSString *)file
                      name:(NSString *)name
              dependencies:(NSArray<NSString *> *)dependencies
       ensureiTerm2Present:(BOOL)ensureiTerm2Present
             pythonVersion:(NSString *)pythonVersion {
    assert(pythonVersion);

    NSString *sanitizedPythonVersion = pythonVersion;
    NSArray<NSString *> *parts = [pythonVersion componentsSeparatedByString:@"."];
    if (parts.count > 2) {
        sanitizedPythonVersion = [[parts subarrayToIndex:2] componentsJoinedByString:@"."];
    }
    if (ensureiTerm2Present && ![dependencies containsObject:@"iterm2"]) {
        dependencies = [@[ @"iterm2" ] arrayByAddingObjectsFromArray:dependencies];
    }
    NSArray<NSString *> *quotedDependencies = [[NSSet setWithArray:dependencies].allObjects mapWithBlock:^id(NSString *anObject) {
        return [NSString stringWithFormat:@"'%@'", anObject];
    }] ?: @[];
    NSString *contents = [NSString stringWithFormat:
                          @"from setuptools import setup\n"
                          @"# WARNING: install_requires must be on one line and contain only quoted strings.\n"
                          @"#          This protects the security of users installing the script.\n"
                          @"#          The script import feature will fail if you try to get fancy.\n"
                          @"setup(name='%@',\n"
                          @"      version='1.0',\n"
                          @"      scripts=['%@/%@.py'],\n"
                          @"      install_requires=[%@],\n"
                          @"      python_requires='=%@'\n"
                          @"      )",
                          name,
                          name,
                          name,
                          [quotedDependencies componentsJoinedByString:@", "],
                          sanitizedPythonVersion];
    [contents writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        NSError *error = nil;
        _content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        if (!_content || error) {
            return nil;
        }
        [self computeName];
        [self computeDependencies];
        [self computePythonVersion];
    }
    return self;
}

- (NSString *)stringByRemovingPythonQuotes:(NSString *)input {
    NSString *regexString = @"^ *['\"]([A-Za-z_0-9-.]+)['\"] *$";

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString
                                                                           options:0
                                                                             error:&error];

    NSString *modifiedString = [regex stringByReplacingMatchesInString:input
                                                               options:0
                                                                 range:NSMakeRange(0, input.length)
                                                          withTemplate:@"$1"];
    if ([input isEqualToString:modifiedString]) {
        return nil;
    }

    return modifiedString;
}

- (NSString *)valueForKeyWithStringValue:(NSString *)key {
    NSString *regex = [NSString stringWithFormat:@"%@='", key];
    NSRange range = [_content rangeOfRegex:regex];
    if (range.location == NSNotFound) {
        return nil;
    }

    NSString *expression = [_content substringFromIndex:NSMaxRange(range)];
    NSUInteger closeQuote = [expression rangeOfRegex:@"'"].location;
    if (closeQuote == NSNotFound) {
        return nil;
    }

    return [expression substringToIndex:closeQuote];
}

- (void)computeName {
    _name = [self valueForKeyWithStringValue:@"name"];
}

- (void)computePythonVersion {
    NSString *expression = [self valueForKeyWithStringValue:@"python_requires"];
    if (!expression) {
        return;
    }
    if (![expression hasPrefix:@"="]) {
        return;
    }
    NSString *version = [expression substringFromIndex:1];
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    if ([parts anyWithBlock:^BOOL(NSString *anObject) {
        return ![anObject isNumeric];
    }]) {
        // Contains a non-numeric value
        return;
    }

    _pythonVersion = version;
}

// Sets one of _dependencies or _dependenciesError
- (void)computeDependencies {
    NSString *regex = @"install_requires *= *\\[";
    NSRange range = [_content rangeOfRegex:regex];
    if (range.location == NSNotFound) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Could not find install_requires in setup.py" };
        _dependenciesError = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:2 userInfo:userInfo];
        return;
    }

    NSString *pythonList = [_content substringFromIndex:NSMaxRange(range)];
    NSUInteger closeBracket = [pythonList rangeOfRegex:@"]"].location;
    if (closeBracket == NSNotFound) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Could not parse install_requires in setup.py" };
        _dependenciesError = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:2 userInfo:userInfo];
        return;
    }

    pythonList = [pythonList substringToIndex:closeBracket];
    NSArray<NSString *> *quotedNames = [pythonList componentsSeparatedByString:@","];
    if (quotedNames.count > 0 && quotedNames.lastObject.length == 0) {
        // The list may end with a dangling comma. We can tolerate that.
        quotedNames = [quotedNames arrayByRemovingLastObject];
    }
    NSArray<NSString *> *names = [quotedNames mapWithBlock:^id(NSString *anObject) {
        return [self stringByRemovingPythonQuotes:anObject];
    }];
    if (names.count != quotedNames.count) {
        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: @"Could not parse install_requires in setup.py" };
        _dependenciesError = [NSError errorWithDomain:@"com.iterm2.scriptarchive" code:2 userInfo:userInfo];
        return;
    }

    _dependencies = [[NSSet setWithArray:names] allObjects];
}

@end
