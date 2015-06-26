//
//  SemanticHistoryTest.m
//  iTerm2
//
//  Created by George Nachman on 12/5/14.
//
//

#import "SemanticHistoryTest.h"
#import "iTermSemanticHistoryController.h"
#import "iTermSemanticHistoryPrefsController.h"
#import "NSFileManager+iTerm.h"

@interface iTermFakeFileManager : NSFileManager
@property(nonatomic, readonly) NSMutableSet *files;
@property(nonatomic, readonly) NSMutableSet *directories;
@property(nonatomic, readonly) NSMutableSet *networkMountPoints;
@end

@implementation iTermFakeFileManager

- (id)init {
    self = [super init];
    if (self) {
        _files = [[NSMutableSet alloc] init];
        _directories = [[NSMutableSet alloc] init];
        _networkMountPoints = [[NSMutableSet alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_files release];
    [_directories release];
    [_networkMountPoints release];
    [super dealloc];
}

- (BOOL)fileExistsAtPath:(NSString *)path isDirectory:(BOOL *)isDirectory {
    if ([_files containsObject:path]) {
        if (isDirectory) {
            *isDirectory = NO;
        }
        return YES;
    }

    if ([_directories containsObject:path]) {
        if (isDirectory) {
            *isDirectory = YES;
        }
        return YES;
    }

    return NO;
}

- (BOOL)fileExistsAtPathLocally:(NSString *)filename {
    for (NSString *networkPath in _networkMountPoints) {
        if ([filename hasPrefix:networkPath]) {
            return NO;
        }
    }

    return [self fileExistsAtPath:filename];
}

- (BOOL)fileExistsAtPath:(NSString *)path {
    return [self fileExistsAtPath:path isDirectory:NULL];
}

@end

@interface TestSemanticHistoryController : iTermSemanticHistoryController
@property(nonatomic, readonly) iTermFakeFileManager *fakeFileManager;
@property(nonatomic, copy) NSArray *scriptArguments;
@property(nonatomic, copy) NSString *openedFile;
@property(nonatomic, copy) NSURL *openedURL;
@property(nonatomic, copy) NSString *openedEditor;
@property(nonatomic, assign) BOOL isTextFile;
@property(nonatomic, assign) BOOL defaultAppIsEditor;
@property(nonatomic, copy) NSString *launchedApp;
@property(nonatomic, copy) NSString *launchedAppArg;
@property(nonatomic, copy) NSString *bundleIdForDefaultApp;
@end

@implementation TestSemanticHistoryController

- (instancetype)init {
    self = [super init];
    if (self) {
        _fakeFileManager = [[iTermFakeFileManager alloc] init];
    }
    return self;
}

- (void)dealloc {
    [_fakeFileManager release];
    [_scriptArguments release];
    [_openedFile release];
    [_openedURL release];
    [_openedEditor release];
    [_launchedApp release];
    [_launchedAppArg release];
    [_bundleIdForDefaultApp release];
    [super dealloc];
}

- (NSFileManager *)fileManager {
    return _fakeFileManager;
}

- (void)launchTaskWithPath:(NSString *)path arguments:(NSArray *)arguments wait:(BOOL)wait {
    self.scriptArguments = arguments;
}

- (BOOL)openFile:(NSString *)fullPath {
    self.openedFile = fullPath;
    return YES;
}

- (BOOL)openURL:(NSURL *)url editorIdentifier:(NSString *)editorIdentifier {
    self.openedURL = url;
    self.openedEditor = editorIdentifier;
    return YES;
}

- (BOOL)isTextFile:(NSString *)path {
    return _isTextFile;
}

- (BOOL)defaultAppForFileIsEditor:(NSString *)file {
    return _defaultAppIsEditor;
}

- (void)launchAppWithBundleIdentifier:(NSString *)bundleIdentifier path:(NSString *)path {
    self.launchedApp = bundleIdentifier;
    self.launchedAppArg = path;
}

- (NSString *)absolutePathForAppBundleWithIdentifier:(NSString *)bundleId {
    return [@"/Applications" stringByAppendingPathComponent:bundleId];
}

- (NSString *)bundleIdForDefaultAppForFile:(NSString *)file {
    if (_bundleIdForDefaultApp) {
        return _bundleIdForDefaultApp;
    } else {
        return [super bundleIdForDefaultAppForFile:file];
    }
}

@end

@interface SemanticHistoryTest ()<iTermSemanticHistoryControllerDelegate>
@end

@implementation SemanticHistoryTest {
    TestSemanticHistoryController *_semanticHistoryController;
    NSString *_coprocessCommand;
}

- (void)setup {
    _semanticHistoryController = [[[TestSemanticHistoryController alloc] init] autorelease];
    _semanticHistoryController.delegate = self;
    _coprocessCommand = nil;
}

#pragma mark - Get Full Path

- (void)testGetFullPathFailsOnNil {
    assert([_semanticHistoryController getFullPath:nil
                                  workingDirectory:@"/"
                                        lineNumber:NULL] == nil);
}

- (void)testGetFullPathFailsOnEmpty {
    assert([_semanticHistoryController getFullPath:@""
                                  workingDirectory:@"/"
                                        lineNumber:NULL] == nil);
}

- (void)testGetFullPathFindsExistingFileAtAbsolutePath {
    NSString *lineNumber = nil;
    static NSString *const kFilename = @"/path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathFindsExistingFileAtRelativePath {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kAbsoluteFilename =
        [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kRelativeFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathStripsParens {
    NSString *lineNumber = nil;
    static NSString *const kFilename = @"/path/to/file";
    NSString *kFilenameWithParens = [NSString stringWithFormat:@"(%@)", kFilename];
    static NSString *const kWorkingDirectory = @"/working/directory";
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kFilenameWithParens
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathStripsTrailingPunctuation {
    for (NSString *punctuation in @[ @".", @")", @",", @":" ]) {
        NSString *lineNumber = nil;
        static NSString *const kFilename = @"/path/to/file";
        NSString *kFilenameWithParens = [kFilename stringByAppendingString:punctuation];
        static NSString *const kWorkingDirectory = @"/working/directory";
        [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
        NSString *actual = [_semanticHistoryController getFullPath:kFilenameWithParens
                                                  workingDirectory:kWorkingDirectory
                                                        lineNumber:&lineNumber];
        NSString *expected = kFilename;
        assert([expected isEqualToString:actual]);
        assert(lineNumber.length == 0);
    }
}

- (void)testGetFullPathExtractsLineNumber {
    NSString *lineNumber = nil;
    static NSString *const kFilename = @"/path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kFilenameWithLineNumber = [kFilename stringByAppendingString:@":123"];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kFilenameWithLineNumber
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.integerValue == 123);
}

- (void)testGetFullPathExtractsLineNumberAndIgnoresColumn {
    NSString *lineNumber = nil;
    static NSString *const kFilename = @"/path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kFilenameWithLineNumber = [kFilename stringByAppendingString:@":123:456"];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kFilenameWithLineNumber
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.integerValue == 123);
}

- (void)testGetFullPathWithParensAndTrailingPunctuationExtractsLineNumber {
    NSString *lineNumber = nil;
    static NSString *const kFilename = @"/path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kFilenameWithLineNumber = [NSString stringWithFormat:@"(%@:123.)", kFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kFilenameWithLineNumber
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.integerValue == 123);
}

- (void)testGetFullPathFailsWithJustStrippedChars {
    NSString *lineNumber = nil;
    static NSString *const kWorkingDirectory = @"/working/directory";
    static NSString *const kFilename = @"(:123.)";
    NSString *actual = [_semanticHistoryController getFullPath:kFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    assert(actual == nil);
}

- (void)testGetFullPathStandardizesDot {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"./path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kAbsoluteFilename = @"/working/directory/path/to/file";
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kRelativeFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathStandardizesDotDot {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"../path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory/blah";
    NSString *kAbsoluteFilename = @"/working/directory/path/to/file";
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kRelativeFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathStripsLeadingASlash {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kAbsoluteFilename =
        [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:[@"a/" stringByAppendingString:kRelativeFilename]
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathStripsLeadingBSlash {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kAbsoluteFilename =
        [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:[@"b/" stringByAppendingString:kRelativeFilename]
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);
    assert(lineNumber.length == 0);
}

- (void)testGetFullPathRejectsNetworkPaths {
    NSString *lineNumber = nil;
    static NSString *const kRelativeFilename = @"path/to/file";
    static NSString *const kWorkingDirectory = @"/working/directory";
    NSString *kAbsoluteFilename =
        [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kAbsoluteFilename];
    NSString *actual = [_semanticHistoryController getFullPath:kRelativeFilename
                                              workingDirectory:kWorkingDirectory
                                                    lineNumber:&lineNumber];
    NSString *expected = kAbsoluteFilename;
    assert([expected isEqualToString:actual]);

    [_semanticHistoryController.fakeFileManager.networkMountPoints addObject:@"/working"];
    actual = [_semanticHistoryController getFullPath:kRelativeFilename
                                    workingDirectory:kWorkingDirectory
                                          lineNumber:&lineNumber];
    assert(actual == nil);
}

#pragma mark - Open Path

- (void)testOpenPathRawAction {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryRawCommandAction,
           kSemanticHistoryTextKey: @"\\1;\\2;\\3;\\4;\\5;\\(test)" };

    NSString *kStringThatIsNotAPath = @"Prefix X Suffix:1";
    BOOL opened = [_semanticHistoryController openPath:kStringThatIsNotAPath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/tmp",
                                                          @"test": @"User Variable" }];
    assert(opened);
    NSString *expectedScript = @"Prefix\\ X\\ Suffix:1;;Prefix;Suffix;/tmp;User Variable";
    NSString *actualScript = _semanticHistoryController.scriptArguments[1];
    assert([expectedScript isEqualToString:actualScript]);
}

- (void)testOpenPathFailsIfFileDoesNotExist {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryBestEditorAction };
    NSString *kStringThatIsNotAPath = @"Prefix X Suffix:1";
    BOOL opened = [_semanticHistoryController openPath:kStringThatIsNotAPath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/tmp" }];
    assert(!opened);
}

- (void)testOpenPathRunsCommandActionForExistingFile {
    NSString *kCommand = @"Command";
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryCommandAction,
           kSemanticHistoryTextKey: kCommand};
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/tmp" }];
    assert(opened);
    assert([kCommand isEqualToString:_semanticHistoryController.scriptArguments[1]]);
}

- (void)testOpenPathRunsCoprocessForExistingFile {
    NSString *kCommand = @"Command";
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryCoprocessAction,
           kSemanticHistoryTextKey: kCommand};
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/tmp" }];
    assert(opened);
    assert([kCommand isEqualToString:_coprocessCommand]);
}

- (void)testOpenPathOpensFileForDirectoryWithURLAction {
    NSString *kCommand = @"Command";
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryUrlAction,
           kSemanticHistoryTextKey: kCommand};
    NSString *kDirectory = @"/directory";
    [_semanticHistoryController.fakeFileManager.directories addObject:kDirectory];
    BOOL opened = [_semanticHistoryController openPath:kDirectory
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/tmp" }];
    assert(opened);
    assert([kDirectory isEqualToString:_semanticHistoryController.openedFile]);
}

- (void)testOpenPathOpensURLWithProperSubstitutions {
    _semanticHistoryController.prefs =
    @{ kSemanticHistoryActionKey: kSemanticHistoryUrlAction,
       kSemanticHistoryTextKey: @"http://foo\\1?line=\\2&prefix=\\3&suffix=\\4&dir=\\5&uservar=\\(test)" };

    NSString *kStringThatIsNotAPath = @"The Path:1";
    [_semanticHistoryController.fakeFileManager.files addObject:@"/The Path"];
    BOOL opened = [_semanticHistoryController openPath:kStringThatIsNotAPath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"The Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"The Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/",
                                                          @"test": @"User Variable" }];
    assert(opened);
    NSURL *expectedURL =
        [NSURL URLWithString:@"http://foo/The%20Path?line=1&prefix=The%20Prefix&suffix=The%20Suffix&dir=/&uservar=User%20Variable"];
    NSURL *actualURL = _semanticHistoryController.openedURL;
    assert([expectedURL isEqual:actualURL]);
    assert(!_semanticHistoryController.openedEditor);
}

- (void)testOpenPathOpensTextFileInEditorWhenEditorIsDefaultApp {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
           kSemanticHistoryEditorKey: kMacVimIdentifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = YES;
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePath
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    NSString *expectedUrlString = [NSString stringWithFormat:@"mvim://open?url=file://%@",
                                   kExistingFileAbsolutePath];
    assert([_semanticHistoryController.openedURL isEqualTo:[NSURL URLWithString:expectedUrlString]]);
    assert(!_semanticHistoryController.openedEditor);
}

- (void)testOpenPathOpensTextFileInEditorWithLineNumberWhenEditorIsDefaultApp {
    _semanticHistoryController.prefs =
    @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
       kSemanticHistoryEditorKey: kMacVimIdentifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *fileWithLineNumber = [kExistingFileAbsolutePath stringByAppendingString:@":12"];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = YES;
    BOOL opened = [_semanticHistoryController openPath:fileWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    NSString *expectedUrlString = [NSString stringWithFormat:@"mvim://open?url=file://%@&line=12",
                                   kExistingFileAbsolutePath];
    assert([_semanticHistoryController.openedURL isEqualTo:[NSURL URLWithString:expectedUrlString]]);
    assert(!_semanticHistoryController.openedEditor);
}

- (void)testOpenPathOpensTextFileAtomEditor {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
           kSemanticHistoryEditorKey: kAtomIdentifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *kExistingFileAbsolutePathWithLineNumber = [kExistingFileAbsolutePath stringByAppendingString:@":12"];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = NO;
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePathWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    assert([kAtomIdentifier isEqualToString:_semanticHistoryController.launchedApp]);
    assert([kExistingFileAbsolutePathWithLineNumber isEqualToString:_semanticHistoryController.launchedAppArg]);
}

- (void)testOpenPathOpensTextFileAtomEditorWhenDefaultAppForThisFile {
    _semanticHistoryController.prefs =
    @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
       kSemanticHistoryEditorKey: kAtomIdentifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *kExistingFileAbsolutePathWithLineNumber = [kExistingFileAbsolutePath stringByAppendingString:@":12"];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = NO;
    _semanticHistoryController.bundleIdForDefaultApp = kAtomIdentifier;  // Act like Atom is the default app for this file
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePathWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    assert([kAtomIdentifier isEqualToString:_semanticHistoryController.launchedApp]);
    assert([kExistingFileAbsolutePathWithLineNumber isEqualToString:_semanticHistoryController.launchedAppArg]);
}

- (void)testOpenPathOpensTextFileSublimeText2Editor {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
           kSemanticHistoryEditorKey: kSublimeText2Identifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *kExistingFileAbsolutePathWithLineNumber =[kExistingFileAbsolutePath stringByAppendingString:@":12"];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = NO;
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePathWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    assert([kSublimeText2Identifier isEqualToString:_semanticHistoryController.launchedApp]);
    assert([kExistingFileAbsolutePathWithLineNumber isEqualToString:_semanticHistoryController.launchedAppArg]);
}

- (void)testOpenPathOpensTextFileSublimeText3Editor {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
           kSemanticHistoryEditorKey: kSublimeText3Identifier };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *kExistingFileAbsolutePathWithLineNumber =[kExistingFileAbsolutePath stringByAppendingString:@":12"];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = NO;
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePathWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    assert([kSublimeText3Identifier isEqualToString:_semanticHistoryController.launchedApp]);
    assert([kExistingFileAbsolutePathWithLineNumber isEqualToString:_semanticHistoryController.launchedAppArg]);
}

- (void)openTextFileInEditorWithIdentifier:(NSString *)editorId
                            expectedScheme:(NSString *)expectedScheme {
    _semanticHistoryController.prefs =
        @{ kSemanticHistoryActionKey: kSemanticHistoryEditorAction,
           kSemanticHistoryEditorKey: editorId };
    NSString *kExistingFileAbsolutePath = @"/file/that/exists";
    NSString *kLineNumber = @":12";
    NSString *kExistingFileAbsolutePathWithLineNumber =
        [kExistingFileAbsolutePath stringByAppendingString:kLineNumber];
    [_semanticHistoryController.fakeFileManager.files addObject:kExistingFileAbsolutePath];
    _semanticHistoryController.isTextFile = YES;
    _semanticHistoryController.defaultAppIsEditor = NO;
    BOOL opened = [_semanticHistoryController openPath:kExistingFileAbsolutePathWithLineNumber
                                      workingDirectory:@"/"
                                         substitutions:@{ kSemanticHistoryPrefixSubstitutionKey: @"Prefix",
                                                          kSemanticHistorySuffixSubstitutionKey: @"Suffix",
                                                          kSemanticHistoryWorkingDirectorySubstitutionKey: @"/" }];
    assert(opened);
    NSString *urlString =
        [NSString stringWithFormat:@"%@://open?url=file://%@&line=%@",
            expectedScheme, kExistingFileAbsolutePath, [kLineNumber substringFromIndex:1]];
    NSURL *expectedURL = [NSURL URLWithString:urlString];
    assert([_semanticHistoryController.openedURL isEqual:expectedURL]);
    if ([editorId isEqualToString:kBBEditIdentifier]) {
        assert([_semanticHistoryController.openedEditor isEqual:kBBEditIdentifier]);
    } else {
        assert(!_semanticHistoryController.openedEditor);
    }
}

- (void)testOpenPathOpensTextFileInMacVim {
    [self openTextFileInEditorWithIdentifier:kMacVimIdentifier expectedScheme:@"mvim"];
}

- (void)testOpenPathOpensTextFileInTextMate {
    [self openTextFileInEditorWithIdentifier:kTextmateIdentifier expectedScheme:@"txmt"];
}

- (void)testOpenPathOpensTextFileInBBEdit {
    // Sadly, BBEdit uses textmate's scheme. This is intentional.
    [self openTextFileInEditorWithIdentifier:kBBEditIdentifier expectedScheme:@"txmt"];
}

// Note there is no test for textmate 2 because it is not directly selectable from the menu and it
// uses the same scheme as textmate, even though its identifier is different.

#pragma mark - Path Of Existing File

- (void)testPathOfExistingFile_Local {
    int numCharsFromPrefix;
    NSString *kWorkingDirectory = @"/directory";
    NSString *kRelativeFilename = @"five six seven eight";
    NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
    NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"one two three four five six "
                                                                            suffix:@"seven eight nine ten eleven"
                                                                  workingDirectory:kWorkingDirectory
                                                              charsTakenFromPrefix:&numCharsFromPrefix];
    assert([kRelativeFilename isEqualToString:path]);
    assert(numCharsFromPrefix == [@"five six " length]);
}

// This test simulates what happens if you select a full line (including hard eol) and do Open Selection.
// The prefix will end in whitespace (maybe) and a newline.
- (void)testPathOfExistingFileIgnoringLeadingAndTrailingWhitespaceAndNewlines {
  int numCharsFromPrefix;
  NSString *kWorkingDirectory = @"/directory";
  NSString *kRelativeFilename = @"five six seven eight";
  NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
  [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
  [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
  NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"five six seven eight \r\n"
                                                                          suffix:@""
                                                                workingDirectory:kWorkingDirectory
                                                            charsTakenFromPrefix:&numCharsFromPrefix];
  assert([kRelativeFilename isEqualToString:path]);
  assert(numCharsFromPrefix == [@"five six seven eight" length]);
}

- (void)testPathOfExistingFileRemovesParens {
    int numCharsFromPrefix;
    NSString *kWorkingDirectory = @"/directory";
    NSString *kRelativeFilename = @"five six seven eight";
    NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
    NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"one two three four (five six "
                                                                            suffix:@"seven eight) nine ten eleven"
                                                                  workingDirectory:kWorkingDirectory
                                                              charsTakenFromPrefix:&numCharsFromPrefix];
    assert([@"five six seven eight" isEqualToString:path]);
    assert(numCharsFromPrefix == [@"five six " length]);
}

- (void)testPathOfExistingFileSupportsLineNumberAndColumnNumber {
    int numCharsFromPrefix;
    NSString *kWorkingDirectory = @"/directory";
    NSString *kRelativeFilename = @"five six seven eight";
    NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
    NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"one two three four five six "
                                                                            suffix:@"seven eight:123:456 nine ten eleven"
                                                                  workingDirectory:kWorkingDirectory
                                                              charsTakenFromPrefix:&numCharsFromPrefix];
    assert([@"five six seven eight:123:456" isEqualToString:path]);
    assert(numCharsFromPrefix == [@"five six " length]);
}

- (void)testPathOfExistingFileSupportsLineNumberAndColumnNumberAndParensAndNonspaceSeparators {
    int numCharsFromPrefix;
    NSString *kWorkingDirectory = @"/directory";
    NSString *kRelativeFilename = @"five.six\tseven eight";
    NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
    NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"one two three four (five.six\t"
                                                                            suffix:@"seven eight:123:456). nine ten eleven"
                                                                  workingDirectory:kWorkingDirectory
                                                              charsTakenFromPrefix:&numCharsFromPrefix];
    assert([@"five.six\tseven eight:123:456" isEqualToString:path]);
    assert(numCharsFromPrefix == [@"five.six\t" length]);
}

- (void)testPathOfExistingFile_IgnoresFilesOnNetworkVolumes {
    int numCharsFromPrefix;
    NSString *kWorkingDirectory = @"/directory";
    NSString *kRelativeFilename = @"five six seven eight";
    NSString *kFilename = [kWorkingDirectory stringByAppendingPathComponent:kRelativeFilename];
    [_semanticHistoryController.fakeFileManager.files addObject:kFilename];
    [_semanticHistoryController.fakeFileManager.networkMountPoints addObject:kWorkingDirectory];
    [_semanticHistoryController.fakeFileManager.directories addObject:kWorkingDirectory];
    NSString *path = [_semanticHistoryController pathOfExistingFileFoundWithPrefix:@"one two three four five six "
                                                                            suffix:@"seven eight nine ten eleven"
                                                                  workingDirectory:kWorkingDirectory
                                                              charsTakenFromPrefix:&numCharsFromPrefix];
    assert(path == nil);
}

#pragma mark - iTermSemanticHistoryControllerDelegate

- (void)semanticHistoryLaunchCoprocessWithCommand:(NSString *)command {
    _coprocessCommand = [[command copy] autorelease];
}

@end
