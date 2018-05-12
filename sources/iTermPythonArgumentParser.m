//
//  iTermPythonArgumentParser.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 5/11/18.
//

#import "iTermPythonArgumentParser.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"

NS_ASSUME_NONNULL_BEGIN

@implementation iTermPythonArgumentParser

- (instancetype)initWithArgs:(NSArray<NSString *> *)args {
    self = [super init];
    if (self) {
        _fullPythonPath = [args[0] copy];
        if (args.count == 0) {
            _args = @[];
        } else {
            _args = [[args subarrayFromIndex:1] copy];
        }
        [self parse];
    }
    return self;
}

- (BOOL)argsLookLikeRepl:(NSArray<NSString *> *)args {
    if ([args[0] isEqualToString:@"aioconsole"]) {
        if (args.count == 1) {
            return YES;
        } else if (args.count == 2 &&
                   [args[1] isEqualToString:@"--no-readline"]) {
            return YES;
        }
    }
    return NO;
}

- (void)parse {
    enum {
        iTermPythonArgumentParserFoundNone,
        iTermPythonArgumentParserFoundModule,
        iTermPythonArgumentParserFoundStatement,
        iTermPythonArgumentParserFoundArgument
    } found = iTermPythonArgumentParserFoundNone;

    NSInteger i = -1;
    for (NSString *arg in _args) {
        i++;
        BOOL ignore = NO;
        switch (found) {
            case iTermPythonArgumentParserFoundNone:
                // Previous argument does not affect how this one is parsed
                break;

            case iTermPythonArgumentParserFoundModule: {
                // If a module is specified that changes how Python parses its command line so we
                // cannot go on.
                if ([self argsLookLikeRepl:[_args subarrayFromIndex:i]]) {
                    // Except for when it's aioconsole with known arguments. That's just the REPL.
                    return;
                }
                // Just glom everything after -m into the module argument because we can't
                // parse it.
                NSArray<NSString *> *moduleArgs = [_args subarrayFromIndex:i];
                _module = [moduleArgs componentsJoinedByString:@" "];
                _escapedModule = [[moduleArgs mapWithBlock:^id(NSString *anObject) {
                    return [anObject stringWithEscapedShellCharactersIncludingNewlines:YES];
                }] componentsJoinedByString:@" "];
                return;
            }

            case iTermPythonArgumentParserFoundStatement:
                // arg follows -c
                _statement = arg;
                return;

            case iTermPythonArgumentParserFoundArgument:
                // arg follows -Q or -W, of which this is the parameter
                ignore = YES;
                break;
        }
        if (ignore) {
            found = iTermPythonArgumentParserFoundNone;
            continue;
        }

        if ([arg isEqualToString:@"-m"]) {
            found = iTermPythonArgumentParserFoundModule;
        } else if ([arg isEqualToString:@"-Q"] ||
                   [arg isEqualToString:@"-W"]) {
            found = iTermPythonArgumentParserFoundArgument;
        } else if ([arg isEqualToString:@"-c"]) {
            found = iTermPythonArgumentParserFoundStatement;
        } else if ([arg isEqualToString:@"-"]) {
            return;
        } else if ([arg hasPrefix:@"-"]) {
            found = iTermPythonArgumentParserFoundNone;
        } else {
            _script = arg;
            return;
        }
    }
}

- (NSString *)escapedScript {
    return [_script stringWithEscapedShellCharactersIncludingNewlines:YES];
}

- (NSString *)escapedStatement {
    return [_statement stringWithEscapedShellCharactersIncludingNewlines:YES];
}

- (NSString *)escapedFullPythonPath {
    return [_fullPythonPath stringWithEscapedShellCharactersIncludingNewlines:YES];
}

@end

NS_ASSUME_NONNULL_END
