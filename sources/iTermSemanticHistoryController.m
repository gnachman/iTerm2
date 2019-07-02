/*
 **  Copyright (c) 2011
 **
 **  Author: Jack Chen (chendo)
 **
 **  Project: iTerm
 **
 **  Description: Terminal Router
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import "iTermSemanticHistoryController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "iTermCachingFileManager.h"
#import "iTermCommandRunner.h"
#import "iTermController.h"
#import "iTermExpressionEvaluator.h"
#import "iTermExpressionParser.h"
#import "iTermLaunchServices.h"
#import "iTermObject.h"
#import "iTermPathCleaner.h"
#import "iTermPathFinder.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSMutableData+iTerm.h"
#import "NSStringITerm.h"
#import "NSURL+iTerm.h"
#import "RegexKitLite.h"
#include <sys/utsname.h>

NSString *const kSemanticHistoryPathSubstitutionKey = @"semanticHistory.path";
NSString *const kSemanticHistoryPrefixSubstitutionKey = @"semanticHistory.prefix";
NSString *const kSemanticHistorySuffixSubstitutionKey = @"semanticHistory.suffix";
NSString *const kSemanticHistoryWorkingDirectorySubstitutionKey = @"semanticHistory.workingDirectory";
NSString *const kSemanticHistoryLineNumberKey = @"semanticHistory.lineNumber";
NSString *const kSemanticHistoryColumnNumberKey = @"semanticHistory.columnNumber";

@interface iTermSemanticHistoryController()<iTermObject>
@end

@implementation iTermSemanticHistoryController {
    iTermExpressionEvaluator *_expressionEvaluator;
    NSMutableArray<iTermCommandRunner *> *_commandRunners;
}

@synthesize prefs = prefs_;
@synthesize delegate = delegate_;

- (instancetype)init {
    self = [super init];
    if (self) {
        _commandRunners = [NSMutableArray array];
    }
    return self;
}

- (NSString *)cleanedUpPathFromPath:(NSString *)path
                             suffix:(NSString *)suffix
                   workingDirectory:(NSString *)workingDirectory
                extractedLineNumber:(NSString **)lineNumber
                       columnNumber:(NSString **)columnNumber {
    iTermPathCleaner *cleaner = [[iTermPathCleaner alloc] initWithPath:path
                                                                suffix:suffix
                                                      workingDirectory:workingDirectory];
    cleaner.fileManager = self.fileManager;
    [cleaner cleanSynchronously];
    if (lineNumber) {
        *lineNumber = cleaner.lineNumber;
    }
    if (columnNumber) {
        *columnNumber = cleaner.columnNumber;
    }
    return cleaner.cleanPath;
}

- (NSString *)preferredEditorIdentifier {
    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryBestEditorAction]) {
        return [iTermSemanticHistoryPrefsController bestEditor];
    } else if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction]) {
        return [iTermSemanticHistoryPrefsController schemeForEditor:prefs_[kSemanticHistoryEditorKey]] ?
            prefs_[kSemanticHistoryEditorKey] : nil;
    } else {
        return nil;
    }
}

- (void)launchAtomWithPath:(NSString *)path {
    [self launchAppWithBundleIdentifier:kAtomIdentifier path:path];
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path {
    if (!path) {
        return;
    }
    [self launchAppWithBundleIdentifier:bundleIdentifier args:@[ path ]];
}

- (NSBundle *)applicationBundleWithIdentifier:(NSString *)bundleIdentifier {
    NSString *bundlePath =
        [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleIdentifier];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    return bundle;
}

- (NSString *)executableInApplicationBundle:(NSBundle *)bundle {
    NSString *executable = [bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    executable = [executable stringByAppendingPathComponent:
                            [bundle objectForInfoDictionaryKey:(id)kCFBundleExecutableKey]];
    return executable;
}

- (NSString *)emacsClientInApplicationBundle:(NSBundle *)bundle {
    DLog(@"Trying to find emacsclient in %@", bundle.bundlePath);
    struct utsname uts;
    int status = uname(&uts);
    if (status) {
        DLog(@"Failed to get uname: %s", strerror(errno));
        return nil;
    }
    NSString *arch = [NSString stringWithUTF8String:uts.machine];
    
    NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    NSMutableArray<NSString *> *bindirs = [NSMutableArray array];
    NSURL *folder = [NSURL fileURLWithPath:[bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"]];
    for (NSURL *url in [[iTermCachingFileManager cachingFileManager] enumeratorAtURL:folder
                                                          includingPropertiesForKeys:nil
                                                                             options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
                                                                        errorHandler:nil]) {
        NSString *file = url.path.lastPathComponent;
        DLog(@"Consider: %@", file);
        if (![file hasPrefix:@"bin-"]) {
            DLog(@"Reject: does not start with bin-");
            continue;
        }
        BOOL isdir = NO;
        [[iTermCachingFileManager cachingFileManager] fileExistsAtPath:url.path isDirectory:&isdir];
        if (!isdir) {
            DLog(@"Reject: not a folder");
            continue;
        }
        [bindirs addObject:file];
    }
    
    // bin-i386-10_5
    NSString *regex = @"^bin-([^-]+)-([0-9]+)_([0-9]+)$";
    NSArray<NSString *> *contenders = [bindirs filteredArrayUsingBlock:^BOOL(NSString *dir) {
        NSArray<NSString *> *captures = [[dir arrayOfCaptureComponentsMatchedByRegex:regex] firstObject];
        DLog(@"Captures for %@ are %@", dir, captures);
        if (captures.count != 4) {
            return NO;
        }
        if (![captures[1] isEqualToString:arch]) {
            return NO;
        }
        if ([captures[2] integerValue] != version.majorVersion) {
            return NO;
        }
        if ([captures[3] integerValue] > version.minorVersion) {
            return NO;
        }
        DLog(@"It's a keeper");
        return YES;
    }];
    
    NSString *best = [contenders maxWithBlock:^NSComparisonResult(NSString *obj1, NSString *obj2) {
        NSArray<NSString *> *cap1 = [obj1 arrayOfCaptureComponentsMatchedByRegex:regex].firstObject;
        NSArray<NSString *> *cap2 = [obj2 arrayOfCaptureComponentsMatchedByRegex:regex].firstObject;
        
        NSInteger minor1 = [cap1[3] integerValue];
        NSInteger minor2 = [cap2[3] integerValue];
        return [@(minor1) compare:@(minor2)];
    }];
    DLog(@"Best is %@", best);
    if (!best) {
        return nil;
    }
    NSString *executable = [bundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS"];
    executable = [executable stringByAppendingPathComponent:best];
    executable = [executable stringByAppendingPathComponent:@"emacsclient"];
    DLog(@"I guess emacsclient is %@", executable);
    return executable;
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier args:(NSArray *)args {
    NSBundle *bundle = [self applicationBundleWithIdentifier:bundleIdentifier];
    if (!bundle) {
        DLog(@"No bundle for %@", bundleIdentifier);
        return;
    }
    NSString *executable = [self executableInApplicationBundle:bundle];
    if (!executable) {
        DLog(@"No executable for %@ in %@", bundleIdentifier, bundle);
        return;
    }
    DLog(@"Launch %@: %@ %@", bundleIdentifier, executable, args);
    [self launchTaskWithPath:executable arguments:args completion:nil];
}

- (void)launchVSCodeWithPath:(NSString *)path {
    assert(path);
    if (!path) {
        // I don't expect this to ever happen.
        return;
    }
    NSString *bundlePath = [self absolutePathForAppBundleWithIdentifier:kVSCodeIdentifier];
    if (bundlePath) {
        NSString *codeExecutable =
        [bundlePath stringByAppendingPathComponent:@"Contents/Resources/app/bin/code"];
        if ([self.fileManager fileExistsAtPath:codeExecutable]) {
            DLog(@"Launch VSCode %@ %@", codeExecutable, path);
            [self launchTaskWithPath:codeExecutable arguments:@[ path, @"-g" ] completion:nil];
        } else {
            // This isn't as good as opening "code -g" because it always opens a new instance
            // of the app but it's the OS-sanctioned way of running VSCode.  We can't
            // use AppleScript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:kVSCodeIdentifier path:path];
        }
    }
}

- (void)launchEmacsWithArguments:(NSArray *)args {
    // Try to find emacsclient.
    NSBundle *bundle = [self applicationBundleWithIdentifier:kEmacsAppIdentifier];
    if (!bundle) {
        DLog(@"Failed to find emacs bundle");
        return;
    }
    NSString *emacsClient = [self emacsClientInApplicationBundle:bundle];
    if (!emacsClient) {
        DLog(@"No emacsClient in %@", bundle);
        DLog(@"Launching emacs the old-fashioned way");
        [self launchAppWithBundleIdentifier:kEmacsAppIdentifier
                                       args:[@[ @"emacs" ] arrayByAddingObjectsFromArray:args]];
        return;
    }

    // Find the regular emacs exectuable to fall back to
    NSString *emacs = [self executableInApplicationBundle:bundle];
    if (!emacs) {
        DLog(@"No executable for emacs in %@", bundle);
        return;
    }
    NSArray<NSString *> *fallbackParts = @[ emacs ];
    NSString *fallback = [[fallbackParts mapWithBlock:^id(NSString *anObject) {
        return [anObject stringWithEscapedShellCharactersIncludingNewlines:YES];
    }] componentsJoinedByString:@" "];
    
    // Run emacsclient -a "emacs <args>" <args>
    // That'll use emacsclient if possible and fall back to real emacs if it fails.
    // Normally it will fail unless you've enabled the daemon.
    [self launchTaskWithPath:emacsClient
                   arguments:[@[ @"-n", @"-a", fallback, args] flattenedArray]
                  completion:nil];

}

- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)bundleId {
    return [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundleId];
}

- (void)launchSublimeTextWithBundleIdentifier:(NSString *)bundleId path:(NSString *)path {
    assert(path);
    if (!path) {
        // I don't expect this to ever happen.
        return;
    }
    NSString *bundlePath = [self absolutePathForAppBundleWithIdentifier:bundleId];
    if (bundlePath) {
        NSString *sublExecutable =
            [bundlePath stringByAppendingPathComponent:@"Contents/SharedSupport/bin/subl"];
        if ([self.fileManager fileExistsAtPath:sublExecutable]) {
            DLog(@"Launch sublime text %@ %@", sublExecutable, path);
            [self launchTaskWithPath:sublExecutable arguments:@[ path ] completion:nil];
        } else {
            // This isn't as good as opening "subl" because it always opens a new instance
            // of the app but it's the OS-sanctioned way of running Sublimetext.  We can't
            // use AppleScript because it won't open the file to a particular line number.
            [self launchAppWithBundleIdentifier:bundleId path:path];
        }
    }
}

+ (NSArray *)bundleIdsThatSupportOpeningToLineNumber {
    return @[ kAtomIdentifier,
              kVSCodeIdentifier,
              kSublimeText2Identifier,
              kSublimeText3Identifier,
              kMacVimIdentifier,
              kTextmateIdentifier,
              kTextmate2Identifier,
              kBBEditIdentifier,
              kEmacsAppIdentifier];
}

- (void)openFile:(NSString *)path
    inEditorWithBundleId:(NSString *)identifier
          lineNumber:(NSString *)lineNumber
        columnNumber:(NSString *)columnNumber {
    if (identifier) {
        DLog(@"openFileInEditor. editor=%@", [self preferredEditorIdentifier]);
        if ([identifier isEqualToString:kAtomIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            [self launchAtomWithPath:path];
        } else if ([identifier isEqualToString:kVSCodeIdentifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            [self launchVSCodeWithPath:path];
        } else if ([identifier isEqualToString:kSublimeText2Identifier] ||
                   [identifier isEqualToString:kSublimeText3Identifier]) {
            if (lineNumber != nil) {
                path = [NSString stringWithFormat:@"%@:%@", path, lineNumber];
            }
            if (columnNumber != nil) {
                path = [path stringByAppendingFormat:@":%@", columnNumber];
            }
            NSString *bundleId;
            if ([identifier isEqualToString:kSublimeText3Identifier]) {
                bundleId = kSublimeText3Identifier;
            } else {
                bundleId = kSublimeText2Identifier;
            }

            [self launchSublimeTextWithBundleIdentifier:bundleId path:path];
        } else if ([identifier isEqualToString:kEmacsAppIdentifier]) {
            NSMutableArray *args = [NSMutableArray array];
            if (path) {
                [args addObject:path];
                if (lineNumber) {
                    if (columnNumber) {
                        [args insertObject:[NSString stringWithFormat:@"+%@:%@", lineNumber, columnNumber] atIndex:0];
                    } else {
                        [args insertObject:[NSString stringWithFormat:@"+%@", lineNumber] atIndex:0];
                    }
                }
            }
            [self launchEmacsWithArguments:args];
        } else {
            path = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
            NSURL *url = nil;
            NSString *editorIdentifier = identifier;
            if (lineNumber) {
                url = [NSURL URLWithString:[NSString stringWithFormat:
                                            @"%@://open?url=file://%@&line=%@",
                                            [iTermSemanticHistoryPrefsController schemeForEditor:editorIdentifier],
                                            path, lineNumber]];
            } else {
                url = [NSURL URLWithString:[NSString stringWithFormat:
                                            @"%@://open?url=file://%@",
                                            [iTermSemanticHistoryPrefsController schemeForEditor:editorIdentifier],
                                            path]];
            }
            DLog(@"Open url %@", url);
            // BBEdit and TextMate share a URL scheme, so this disambiguates.
            [self openURL:url editorIdentifier:editorIdentifier];
        }
    }
}

- (void)openFileInEditor:(NSString *)path lineNumber:(NSString *)lineNumber columnNumber:(NSString *)columnNumber {
    [self openFile:path inEditorWithBundleId:[self preferredEditorIdentifier] lineNumber:lineNumber columnNumber:columnNumber];
}

- (BOOL)activatesOnAnyString {
    return [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
}

- (void)launchTaskWithPath:(NSString *)path
                 arguments:(NSArray *)arguments
                completion:(void (^)(void))completion {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_enter(group);
    __weak __typeof(self) weakSelf = self;
    [self _launchTaskWithPath:path arguments:arguments completion:^(iTermBufferedCommandRunner *runner, int status) {
        [weakSelf didFinishCommand:[@[path ?: @""] arrayByAddingObjectsFromArray:arguments]
                        withStatus:status
                            runner:runner];
        dispatch_group_leave(group);
    }];
    if (completion) {
        dispatch_group_notify(group, dispatch_get_main_queue(), completion);
    }
}

- (void)didFinishCommand:(NSArray *)parts
              withStatus:(int)status
                  runner:(iTermBufferedCommandRunner *)runner {
    [_commandRunners removeObject:runner];
    DLog(@"Runner %@ finished with status %@. There are now %@ runners.", runner, @(status), @(_commandRunners.count));
    if (!status) {
        return;
    }
    iTermWarning *warning = [[iTermWarning alloc] init];
    warning.title = [NSString stringWithFormat:@"The following command returned a non-zero exit code:\n\n“%@”",
                     [parts componentsJoinedByString:@" "]];
    warning.heading = @"Semantic History Command Failed";
    static const iTermSingleUseWindowOptions options = iTermSingleUseWindowOptionsShortLived;
    NSMutableData *inject = [runner.output mutableCopy];
    NSString *truncationWarning = [NSString stringWithFormat:@"\n%c[m;[output truncated]\n", 27];
    if (runner.truncated) {
        [inject appendData:[truncationWarning dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [inject it_replaceOccurrencesOfData:[NSData dataWithBytes:"\n" length:1]
                               withData:[NSData dataWithBytes:"\r\n" length:2]];
    warning.warningActions = @[ [iTermWarningAction warningActionWithLabel:@"OK" block:nil],
                                [iTermWarningAction warningActionWithLabel:@"View" block:^(iTermWarningSelection selection) {
                                    [[iTermController sharedInstance] openSingleUseWindowWithCommand:@"/usr/bin/true"
                                                                                              inject:inject
                                                                                         environment:nil
                                                                                                 pwd:@"/"
                                                                                             options:options
                                                                                          completion:nil];
                                }] ];
    warning.warningType = kiTermWarningTypePermanentlySilenceable;
    NSString *name;
    if ([parts[0] isEqualToString:@"/bin/sh"] && [parts[1] isEqualToString:@"-c"] && parts.count > 2) {
        name = parts[2];
    } else {
        name = parts[0];
    }
    warning.identifier = [@"NoSyncSemanticHistoryCommandFailed_" stringByAppendingString:name];
    [warning runModal];
}

- (void)_launchTaskWithPath:(NSString *)path
                  arguments:(NSArray *)arguments
                 completion:(void (^)(iTermBufferedCommandRunner *runner, int status))completion {
    iTermBufferedCommandRunner *runner =
    [[iTermBufferedCommandRunner alloc] initWithCommand:path
                                          withArguments:arguments
                                                   path:[[NSFileManager defaultManager] currentDirectoryPath]];
    DLog(@"Launch %@ %@ in runner %@", path, arguments, runner);
    runner.maximumOutputSize = @(1024 * 10);
    __weak __typeof(runner) weakRunner = runner;
    __weak __typeof(self) weakSelf = self;
    runner.completion = ^(int status) {
        __strong __typeof(runner) strongRunner = weakRunner;
        __strong __typeof(self) strongSelf = weakSelf;
        DLog(@"Command finished");
        if (strongSelf && strongRunner) {
            [strongSelf->_commandRunners removeObject:strongRunner];
            completion(strongRunner, status);
        }
    };
    [_commandRunners addObject:runner];
    [runner run];
}

- (BOOL)openFile:(NSString *)fullPath {
    DLog(@"Open file %@", fullPath);
    return [[iTermLaunchServices sharedInstance] openFile:fullPath];
}

- (BOOL)openURL:(NSURL *)url editorIdentifier:(NSString *)editorIdentifier {
    DLog(@"Open URL %@", url);
    if (editorIdentifier) {
        return [[NSWorkspace sharedWorkspace] openURLs:@[ url ]
                               withAppBundleIdentifier:editorIdentifier
                                               options:NSWorkspaceLaunchDefault
                        additionalEventParamDescriptor:nil
                                     launchIdentifiers:NULL];
    } else {
        return [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (BOOL)openURL:(NSURL *)url {
    return [self openURL:url editorIdentifier:nil];
}

- (NSDictionary *)numericSubstitutions {
    return @{ @"\\1": @"\\(semanticHistory.path)",
              @"\\2": @"\\(semanticHistory.lineNumber)",
              @"\\3": @"\\(semanticHistory.prefix)",
              @"\\4": @"\\(semanticHistory.suffix)",
              @"\\5": @"\\(semanticHistory.workingDirectory)" };
}

- (NSTimeInterval)evaluationTimeout {
    return 30;
}

- (void)openPath:(NSString *)cleanedUpPath
   orRawFilename:(NSString *)rawFileName
   substitutions:(NSDictionary *)substitutions
           scope:(iTermVariableScope *)originalScope
      lineNumber:(NSString *)lineNumber
    columnNumber:(NSString *)columnNumber
      completion:(void (^)(BOOL))completion {
    DLog(@"openPath:%@ rawFileName:%@ substitutions:%@ lineNumber:%@ columnNumber:%@",
         cleanedUpPath, rawFileName, substitutions, lineNumber, columnNumber);

    NSString *path;
    BOOL isRawAction = [prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryRawCommandAction];
    if (isRawAction) {
        path = rawFileName;
        lineNumber = @"";
        columnNumber = @"";
        DLog(@"Is a raw action. Use path %@", rawFileName);
    } else {
        path = cleanedUpPath;
        DLog(@"Not a raw action. New path is %@, line number is %@", path, lineNumber);
    }

    // Construct a scope with semanticHistory.xxx variables based on the passed-in scope
    iTermVariables *frame = [[iTermVariables alloc] initWithContext:iTermVariablesSuggestionContextNone owner:self];
    iTermVariableScope *scope = [originalScope copy];
    [scope addVariables:frame toScopeNamed:@"semanticHistory"];
    [scope setValuesFromDictionary:substitutions];
    NSString *const escapedPath = [path stringWithEscapedShellCharactersIncludingNewlines:YES];
    [scope setValue:escapedPath forVariableNamed:kSemanticHistoryPathSubstitutionKey];
    [scope setValue:lineNumber forVariableNamed:kSemanticHistoryLineNumberKey];
    [scope setValue:columnNumber forVariableNamed:kSemanticHistoryColumnNumberKey];

    NSDictionary *numericSubstitutions = [self numericSubstitutions];
    NSString *script = [prefs_ objectForKey:kSemanticHistoryTextKey];
    script = [script stringByPerformingSubstitutions:numericSubstitutions];
    _expressionEvaluator = [[iTermExpressionEvaluator alloc] initWithInterpolatedString:script scope:scope];

    if (isRawAction) {
        __weak __typeof(self) weakSelf = self;
        [_expressionEvaluator evaluateWithTimeout:self.evaluationTimeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
            DLog(@"Launch raw action: /bin/sh -c %@", evaluator.value);
            if (evaluator.error) {
                completion(YES);
                return;
            }
            [weakSelf launchTaskWithPath:@"/bin/sh"
                               arguments:@[ @"-c", evaluator.value ?: @"" ]
                               completion:^{
                                   completion(YES);
                               }];
        }];
        return;
    }

    BOOL isDirectory;
    if (![self.fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
        DLog(@"No file exists at %@, not running semantic history", path);
        completion(NO);
        return;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryCommandAction]) {
        __weak __typeof(self) weakSelf = self;
        [_expressionEvaluator evaluateWithTimeout:self.evaluationTimeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
            DLog(@"Running /bin/sh -c %@", evaluator.value);
            if (evaluator.error) {
                completion(YES);
                return;
            }
            [weakSelf launchTaskWithPath:@"/bin/sh"
                               arguments:@[ @"-c", evaluator.value ?: @"" ]
                              completion:^{
                                  completion(YES);
                              }];
        }];
        return;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryCoprocessAction]) {
        __weak __typeof(self) weakSelf = self;
        [_expressionEvaluator evaluateWithTimeout:self.evaluationTimeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
            DLog(@"Launch coprocess with script %@", evaluator.value);
            if (evaluator.error) {
                completion(YES);
            }
            [weakSelf.delegate semanticHistoryLaunchCoprocessWithCommand:evaluator.value];
            completion(YES);
        }];
        return;
    }

    if (isDirectory) {
        DLog(@"Open directory %@", path);
        [self openFile:path];
        completion(YES);
        return;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryUrlAction]) {
        NSString *url = prefs_[kSemanticHistoryTextKey];
        // Replace the path with a non-shell-escaped path since we perform escaping later in this code path.
        [scope setValue:path ?: @"" forVariableNamed:kSemanticHistoryPathSubstitutionKey];

        url = [url stringByPerformingSubstitutions:numericSubstitutions];
        NSString *(^urlEscapeFunction)(NSString *) = ^NSString *(NSString *string) {
            return [string stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]];
        };
        iTermParsedExpression *parsedExpression = [iTermExpressionParser parsedExpressionWithInterpolatedString:url
                                                                                               escapingFunction:urlEscapeFunction
                                                                                                          scope:scope];
        _expressionEvaluator = [[iTermExpressionEvaluator alloc] initWithParsedExpression:parsedExpression
                                                                               invocation:url
                                                                                    scope:scope];
        // Add percent escapes substitutions
        _expressionEvaluator.escapingFunction = urlEscapeFunction;
        __weak __typeof(self) weakSelf = self;
        [_expressionEvaluator evaluateWithTimeout:self.evaluationTimeout completion:^(iTermExpressionEvaluator * _Nonnull evaluator) {
            DLog(@"URL format is %@. Error is %@. Evaluated value is %@.", url, evaluator.error, evaluator.value);
            if (!evaluator.error) {
                [weakSelf openURL:[NSURL URLWithUserSuppliedString:evaluator.value]];
            } else {
                [weakSelf openURL:[NSURL URLWithUserSuppliedString:url]];
            }
            completion(YES);
        }];
        return;
    }

    if ([prefs_[kSemanticHistoryActionKey] isEqualToString:kSemanticHistoryEditorAction] &&
        [self preferredEditorIdentifier]) {
        // Action is to open in a specific editor, so open it in the editor.
        [self openFileInEditor:path lineNumber:lineNumber columnNumber:columnNumber];
        completion(YES);
        return;
    }

    if (lineNumber) {
        NSString *appBundleId = [self bundleIdForDefaultAppForFile:path];
        if ([self canOpenFileWithLineNumberUsingEditorWithBundleId:appBundleId]) {
            DLog(@"A line number is present and I know how to open this file to the line number using %@. Do so.",
                 appBundleId);
            [self openFile:path inEditorWithBundleId:appBundleId lineNumber:lineNumber columnNumber:columnNumber];
            completion(YES);
            return;
        }
    }

    [self openFile:path];
    completion(YES);
}

- (BOOL)canOpenFileWithLineNumberUsingEditorWithBundleId:(NSString *)appBundleId {
    return [[self.class bundleIdsThatSupportOpeningToLineNumber] containsObject:appBundleId];
}

- (NSString *)bundleIdForDefaultAppForFile:(NSString *)file {
    NSURL *fileUrl = [NSURL fileURLWithPath:file];
    return [self bundleIdForDefaultAppForURL:fileUrl];
}

- (NSString *)bundleIdForDefaultAppForURL:(NSURL *)fileUrl {
    NSURL *appUrl = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:fileUrl];
    if (!appUrl) {
        return nil;
    }

    NSBundle *appBundle = [NSBundle bundleWithURL:appUrl];
    if (!appBundle) {
        return nil;
    }
    return [appBundle bundleIdentifier];
}

- (BOOL)defaultAppForFileIsEditor:(NSString *)file {
    return [iTermSemanticHistoryPrefsController bundleIdIsEditor:[self bundleIdForDefaultAppForFile:file]];
}

- (NSString *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                         suffix:(NSString *)afterStringIn
                               workingDirectory:(NSString *)workingDirectory
                           charsTakenFromPrefix:(int *)charsTakenFromPrefixPtr
                           charsTakenFromSuffix:(int *)charsTakenFromSuffixPtr
                                 trimWhitespace:(BOOL)trimWhitespace {
    iTermPathFinder *pathfinder = [[iTermPathFinder alloc] initWithPrefix:beforeStringIn
                                                                   suffix:afterStringIn
                                                         workingDirectory:workingDirectory
                                                           trimWhitespace:trimWhitespace];
    pathfinder.fileManager = self.fileManager;
    [pathfinder searchSynchronously];
    if (charsTakenFromPrefixPtr) {
        *charsTakenFromPrefixPtr = pathfinder.prefixChars;
    }
    if (charsTakenFromSuffixPtr) {
        *charsTakenFromSuffixPtr = pathfinder.suffixChars;
    }
    return pathfinder.path;
}

- (iTermPathFinder *)pathOfExistingFileFoundWithPrefix:(NSString *)beforeStringIn
                                                suffix:(NSString *)afterStringIn
                                      workingDirectory:(NSString *)workingDirectory
                                        trimWhitespace:(BOOL)trimWhitespace
                                            completion:(void (^)(NSString *path, int prefixChars, int suffixChars))completion {
    iTermPathFinder *pathfinder = [[iTermPathFinder alloc] initWithPrefix:beforeStringIn
                                                                   suffix:afterStringIn
                                                         workingDirectory:workingDirectory
                                                           trimWhitespace:trimWhitespace];
    pathfinder.fileManager = self.fileManager;
    __weak __typeof(pathfinder) weakPathfinder = pathfinder;
    [pathfinder searchWithCompletion:^{
        __strong __typeof(pathfinder) strongPathfinder = weakPathfinder;
        if (!strongPathfinder) {
            return;
        }
        completion(strongPathfinder.path, strongPathfinder.prefixChars, strongPathfinder.suffixChars);
    }];
    return pathfinder;
}

- (NSFileManager *)fileManager {
    return [iTermCachingFileManager cachingFileManager];
}

#pragma mark - iTermObject

- (iTermBuiltInFunctions *)objectMethodRegistry {
    return nil;
}

- (iTermVariableScope *)objectScope {
    return nil;
}

@end
