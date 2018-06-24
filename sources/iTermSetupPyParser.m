//
//  iTermSetupPyParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 6/24/18.
//

#import "iTermSetupPyParser.h"

#import "NSArray+iTerm.h"
#import "RegexKitLite.h"

@implementation iTermSetupPyParser {
    NSArray<NSString *> *_dependencies;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        NSError *error = nil;
        _content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        if (!_content || error) {
            return nil;
        }
        [self computeDependencies];
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

    _dependencies = names;
}

@end
