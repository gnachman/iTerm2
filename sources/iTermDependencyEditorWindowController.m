//
//  iTermDependencyEditorWindowController.m
//  iTerm2
//
//  Created by George Nachman on 1/12/19.
//

#import "iTermDependencyEditorWindowController.h"

#import "DebugLogging.h"
#import "iTermAPIScriptLauncher.h"
#import "iTermApplicationDelegate.h"
#import "iTermController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptsMenuController.h"
#import "iTermSetupCfgParser.h"
#import "iTermTuple.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSFileManager+iTerm.h"
#import "NSStringITerm.h"
#import "NSTextField+iTerm.h"

#import <Sparkle/Sparkle.h>

@interface iTermDependencyEditorWindowController ()<NSTableViewDataSource, NSTableViewDelegate>

@end

@implementation iTermDependencyEditorWindowController {
    IBOutlet NSPopUpButton *_scriptsButton;
    IBOutlet NSPopUpButton *_pythonVersionButton;
    IBOutlet NSTableView *_tableView;
    IBOutlet NSButton *_checkForUpdate;
    IBOutlet NSButton *_remove;
    IBOutlet NSView *_mainView;
    IBOutlet NSView *_upgradeContainer;
    NSMutableArray<iTermScriptItem *> *_scriptItems;
    NSArray<iTermTuple<NSString *, NSString *> *> *_packageTuples;
    iTermScriptItem *_selectedScriptItem;
    NSString *_pythonVersion;
}

+ (instancetype)sharedInstance {
    if (![[NSFileManager defaultManager] homeDirectoryDotDir]) {
        return nil;
    }
    static id instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] initWithWindowNibName:@"iTermDependencyEditorWindowController"];
    });
    return instance;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self reload];
}

- (void)open {
    if (self.windowLoaded) {
        iTermScriptItem *selectedItem = _selectedScriptItem;
        [self reload];
        NSInteger index = [_scriptItems indexOfObject:selectedItem];
        if (index != NSNotFound) {
            [_scriptsButton selectItemAtIndex:index];
            [self didSelectScriptAtIndex:index];
        }
    }
    [self.window makeKeyAndOrderFront:nil];
}

#pragma mark - Private

- (void)reload {
    [self populateScripts];
    if (_scriptItems.count) {
        [self didSelectScriptAtIndex:0];
    }
}

- (void)fetchVersionOfPackage:(NSString *)packageName completion:(void (^)(BOOL ok, NSString *result))completion {
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptItem.path];
    [[iTermPythonRuntimeDownloader sharedInstance] runPip3InContainer:container
                                                        pythonVersion:_pythonVersion
                                                        withArguments:@[ @"show", packageName ]
                                                           completion:^(BOOL ok, NSData *output) {
                                                               if (!ok) {
                                                                   completion(NO, [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]);
                                                                   return;
                                                               } else {
                                                                   NSString *version = [self versionInPipOutput:output];
                                                                   completion(YES, version);
                                                               }
                                                           }];
}

- (void)loadPackageAtIndex:(NSInteger)index {
    [self loadPackageAtIndex:index completion:nil];
}

- (void)loadPackageAtIndex:(NSInteger)index completion:(void (^)(BOOL ok, NSString *result))completion {
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptItem.path];
    iTermTuple<NSString *, NSString *> *tuple = _packageTuples[index];
    __weak __typeof(self) weakSelf = self;
    [self fetchVersionOfPackage:tuple.firstObject completion:^(BOOL ok, NSString *result) {
        const BOOL accepted = [weakSelf didFetchVersionOfPackageAtIndex:index originalTuple:tuple container:container ok:ok result:result];
        if (accepted && completion) {
            completion(ok, result);
        }
    }];
}

- (BOOL)didFetchVersionOfPackageAtIndex:(NSInteger)index
                          originalTuple:(iTermTuple *)tuple
                              container:(NSURL *)container
                                     ok:(BOOL)ok
                                 result:(NSString *)result {
    if (index < 0 || index >= _packageTuples.count) {
        return NO;
    }
    if (_packageTuples[index] != tuple) {
        return NO;
    }
    if (!ok) {
        tuple.secondObject = @"[Error]";
        DLog(@"Error running pip3 show %@ in %@: %@",
             tuple.firstObject,
             container.path,
             result);
    } else {
        tuple.secondObject = result;
    }
    [self->_tableView beginUpdates];
    [self->_tableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:index]
                                columnIndexes:[NSIndexSet indexSetWithIndex:1]];  // Index 1 is version
    [self->_tableView endUpdates];
    return YES;
}

- (NSString *)versionInPipOutput:(NSData *)output {
    NSString *string = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [string componentsSeparatedByString:@"\n"];
    NSString *const versionPrefix = @"Version: ";
    NSString *versionLine = [lines filteredArrayUsingBlock:^BOOL(NSString *aLine) {
        return [aLine hasPrefix:versionPrefix];
    }].firstObject;
    return [versionLine substringFromIndex:versionPrefix.length];
}

- (void)didSelectScriptAtIndex:(NSInteger)index {
    _checkForUpdate.enabled = NO;
    _remove.enabled = NO;
    _selectedScriptItem = _scriptItems[index];

    const BOOL fullEnvironment = _selectedScriptItem.fullEnvironment;
    _mainView.hidden = !fullEnvironment;
    _upgradeContainer.hidden = fullEnvironment;
    if (!fullEnvironment) {
        return;
    }

    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:[_selectedScriptItem.path stringByAppendingPathComponent:@"setup.cfg"]];
    _packageTuples = [[parser.dependencies mapWithBlock:^id(NSString *dep) {
        iTermTuple *tuple = [iTermTuple tupleWithObject:dep andObject:@""];
        return tuple;
    }] sortedArrayUsingComparator:^NSComparisonResult(iTermTuple * _Nonnull tuple1, iTermTuple * _Nonnull tuple2) {
        return [tuple1.firstObject compare:tuple2.firstObject];
    }];
    [self loadPythonVersionsSelecting:parser.pythonVersion.it_twoPartVersionNumber];
    for (NSInteger i = 0; i < _packageTuples.count; i++) {
        [self loadPackageAtIndex:i];
    }
    [_tableView reloadData];
}

- (void)loadPythonVersionsSelecting:(NSString *)selectedVersion {
    NSString *const env = [[_selectedScriptItem.path stringByAppendingPathComponent:@"iterm2env"] stringByAppendingPathComponent:@"versions"];
    _pythonVersion = selectedVersion ?: [iTermPythonRuntimeDownloader bestPythonVersionAt:env];
    NSArray<NSString *> *versions = [[[[iTermPythonRuntimeDownloader pythonVersionsAt:env] mapWithBlock:^id(NSString *version) {
        return version.it_twoPartVersionNumber;
    }] sortedArrayUsingSelector:@selector(compare:)] uniq];
    [_pythonVersionButton.menu removeAllItems];
    for (NSString *version in versions) {
        [_pythonVersionButton addItemWithTitle:version];
    }
    _pythonVersionButton.title = _pythonVersion;
    [_pythonVersionButton selectItemAtIndex:[versions indexOfObject:_pythonVersion]];
}

- (void)populateScripts {
    _scriptItems = [NSMutableArray array];
    _checkForUpdate.enabled = NO;
    _remove.enabled = NO;
    [_scriptsButton.menu removeAllItems];
    iTermApplicationDelegate *itad = [iTermApplication.sharedApplication delegate];
    [self addScriptItems:[itad.scriptsMenuController scriptItems] breadcrumbs:@[]];
}

- (void)addScriptItems:(NSArray<iTermScriptItem *> *)scriptItems breadcrumbs:(NSArray<NSString *> *)breadcrumbs {
    for (iTermScriptItem *item in [scriptItems sortedArrayUsingComparator:^NSComparisonResult(iTermScriptItem * _Nonnull obj1, iTermScriptItem * _Nonnull obj2) {
        return [obj1.name compare:obj2.name];
    }]) {
        if (item.isFolder) {
            [self addScriptItems:item.children breadcrumbs:[breadcrumbs arrayByAddingObject:item.name]];
            continue;
        }
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[[breadcrumbs arrayByAddingObject:item.name] componentsJoinedByString:@"/"]
                                                          action:nil
                                                   keyEquivalent:@""];
        menuItem.tag = _scriptItems.count;
        [_scriptsButton.menu addItem:menuItem];
        [_scriptItems addObject:item];
    }
}

- (void)pip3UpgradeDidFinish:(iTermTuple<NSString *, NSString *> *)tuple
                       index:(NSInteger)index
                  scriptPath:(NSString *)scriptPath {
    if (_packageTuples.count <= index) {
        return;
    }
    if (_packageTuples[index] == tuple) {
        [self loadPackageAtIndex:index completion:^(BOOL ok, NSString *result) {
            if (!ok) {
                return;
            }
            [iTermDependencyEditorWindowController setDependency:[NSString stringWithFormat:@"%@>=%@", tuple.firstObject, result]
                                                      scriptPath:scriptPath];
        }];
    }
}

- (void)pip3UninstallDidFinish:(iTermTuple<NSString *, NSString *> *)tuple
                         index:(NSInteger)index
            selectedScriptPath:(NSString *)selectedScriptPath {
    if (_packageTuples.count <= index) {
        return;
    }
    if (_packageTuples[index] != tuple) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [self fetchVersionOfPackage:tuple.firstObject completion:^(BOOL ok, NSString *result) {
        [weakSelf uninstallDidFetchPackageVersionSuccessfully:ok
                                                      package:tuple.firstObject
                                           selectedScriptPath:selectedScriptPath];
    }];
}

- (void)uninstallDidFetchPackageVersionSuccessfully:(BOOL)ok
                                            package:(NSString *)package
                                 selectedScriptPath:(NSString *)selectedScriptPath {
    if (ok) {
        [self uninstallDidFailForPackage:package];
        return;
    }

    NSString *path = [selectedScriptPath stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:path];
    [iTermSetupCfgParser writeSetupCfgToFile:path
                                        name:parser.name
                                dependencies:[parser.dependencies arrayByRemovingObject:package]
                         ensureiTerm2Present:NO
                               pythonVersion:parser.pythonVersion
                          environmentVersion:parser.minimumEnvironmentVersion];

    [self didSelectScriptAtIndex:_scriptsButton.indexOfSelectedItem];
}

- (NSString *)requestDependencyName {
    NSString *newDependencyName = nil;
    do {
        NSTextField *textField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
        [textField setEditable:YES];
        [textField setSelectable:YES];

        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.heading = @"Add Dependency";
        warning.title = @"What dependency would you like to add?";
        warning.actionLabels = @[ @"OK", @"Cancel" ];
        warning.accessory = textField;
        warning.warningType = kiTermWarningTypePersistent;
        warning.window = self.window;
        warning.initialFirstResponder = textField;
        iTermWarningSelection selection = [warning runModal];
        if (selection == kiTermWarningSelection1) {
            return nil;
        }
        newDependencyName = [textField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } while (newDependencyName.length == 0);
    return newDependencyName;
}

- (void)runPip3WithArguments:(NSArray<NSString *> *)arguments completion:(void (^)(void))completion {
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptItem.path];
    NSString *pip3 = [[iTermPythonRuntimeDownloader sharedInstance] pip3At:[container.path stringByAppendingPathComponent:@"iterm2env"]
                                                             pythonVersion:_pythonVersion];
    NSString *command =
    [[pip3 stringWithBackslashEscapedShellCharactersIncludingNewlines:YES]
     stringByAppendingFormat:@" %@", [[arguments mapWithBlock:^id(NSString *anObject) {
        return [anObject stringWithBackslashEscapedShellCharactersIncludingNewlines:YES];
    }] componentsJoinedByString:@" "]];
    iTermWarningSelection selection = [iTermWarning showWarningWithTitle:command
                                                                 actions:@[ @"OK", @"Cancel" ]
                                                               accessory:nil
                                                              identifier:@"DependencyEditorPip3Confirmation"
                                                             silenceable:kiTermWarningTypePersistent
                                                                 heading:@"Run this Command?"
                                                                  window:self.window];
    if (selection == kiTermWarningSelection1) {
        return;
    }
    // Escape the path to pip3 because it gets evaluated as a swifty string.
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:pip3
                                                           arguments:arguments
                                                              inject:nil
                                                         environment:nil
                                                                 pwd:nil
                                                             options:iTermSingleUseWindowOptionsCommandNotSwiftyString
                                                      didMakeSession:nil
                                                          completion:^{
                                                              completion();
                                                          }];
}

- (void)pip3InstallDidFinish:(NSString *)selectedScriptPath newDependencyName:(NSString *)newDependencyName {
    if (![selectedScriptPath isEqualToString:_selectedScriptItem.path]) {
        return;
    }
    __weak __typeof(self) weakSelf = self;
    [self fetchVersionOfPackage:newDependencyName completion:^(BOOL ok, NSString *result) {
        [weakSelf installDidFinishSuccessfully:ok selectedScriptPath:selectedScriptPath newDependencyName:newDependencyName];
    }];
}

- (void)uninstallDidFailForPackage:(NSString *)package {
    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Uninstall of %@ failed. Check the output of pip3 for errors.",package]
                               actions:@[ @"OK" ]
                             accessory:nil
                            identifier:@"DependencyEditorInstallationFailed"
                           silenceable:kiTermWarningTypePersistent
                               heading:@"Removal Failed"
                                window:self.window];
}

- (void)installDidFinishSuccessfully:(BOOL)ok
                  selectedScriptPath:(NSString *)selectedScriptPath
                   newDependencyName:(NSString *)newDependencyName {
    if (!ok) {
        [iTermWarning showWarningWithTitle:@"Check the output of pip3 for errors."
                                   actions:@[ @"OK" ]
                                 accessory:nil
                                identifier:@"DependencyEditorInstallationFailed"
                               silenceable:kiTermWarningTypePersistent
                                   heading:@"Installation Failed"
                                    window:self.window];
        return;
    }
    if (![selectedScriptPath isEqualToString:_selectedScriptItem.path]) {
        return;
    }
    NSString *path = [selectedScriptPath stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:path];
    [iTermSetupCfgParser writeSetupCfgToFile:path
                                        name:parser.name
                                dependencies:[parser.dependencies arrayByAddingObject:newDependencyName]
                         ensureiTerm2Present:NO
                               pythonVersion:parser.pythonVersion
                          environmentVersion:parser.minimumEnvironmentVersion];
    [self didSelectScriptAtIndex:_scriptsButton.selectedTag];
}

+ (void)setDependency:(NSString *)dependency scriptPath:(NSString *)scriptPath {
    DLog(@"Set dependency %@ in %@", dependency, scriptPath);
    NSString *path = [scriptPath stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:path];
    [iTermSetupCfgParser writeSetupCfgToFile:path
                                        name:parser.name
                                dependencies:[parser.dependencies ?: @[] arrayBySettingPythonDependency:dependency]
                         ensureiTerm2Present:NO
                               pythonVersion:parser.pythonVersion
                          environmentVersion:parser.minimumEnvironmentVersion];
}

#pragma mark - Actions

- (IBAction)upgrade:(id)sender {
    if (!_selectedScriptItem) {
        return;
    }

    NSString *name = _selectedScriptItem.path.lastPathComponent.stringByDeletingPathExtension;
    NSURL *folder = [[[NSURL fileURLWithPath:_selectedScriptItem.path] URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
    if ([[NSFileManager defaultManager] fileExistsAtPath:folder.path]) {
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = [NSString stringWithFormat:@"Can’t upgrade because %@ already exists", folder.path];
        warning.heading = @"Error";
        warning.actionLabels = @[ @"OK" ];
        warning.warningType = kiTermWarningTypePersistent;
        warning.window = self.window;
        [warning runModal];
        return;
    }

    iTermScriptItem *item = _selectedScriptItem;
    __weak __typeof(self) weakSelf = self;
    NSString *pythonVersion =
    [iTermAPIScriptLauncher inferredPythonVersionFromScriptAt:item.path];
    [[iTermPythonRuntimeDownloader sharedInstance] installPythonEnvironmentTo:folder
                                                                 dependencies:@[]
                                                                pythonVersion:pythonVersion
                                                                   completion:^(BOOL ok) {
        if (!ok) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Installation Failed";
            alert.informativeText = @"Please file a bug report at https://iterm2.com/bugs.";
            [alert runModal];
            return;
        }
        [weakSelf finishUpgradingScriptItem:item toFullEnvironmentAt:folder];
        // TODO: Rebuild menus
    }];
}

- (void)finishUpgradingScriptItem:(iTermScriptItem *)item
              toFullEnvironmentAt:(NSURL *)url {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    // Create Scripts/Foo/Foo
    NSString *innerFolder = [url.path stringByAppendingPathComponent:url.path.lastPathComponent];
    NSError *error = nil;
    [fileManager createDirectoryAtPath:innerFolder
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&error];
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Installation Failed";
        alert.informativeText = [NSString stringWithFormat:@"Error creating %@: %@", innerFolder, error.localizedDescription];
        [alert runModal];
        return;
    }
    // Move Scripts/Foo.py to Scripts/Foo/Foo/Foo.py
    NSString *name = item.path.lastPathComponent;
    NSString *destination = [innerFolder stringByAppendingPathComponent:name];
    [fileManager moveItemAtPath:item.path
                         toPath:destination
                          error:&error];
    if (error) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Installation Failed";
        alert.informativeText = [NSString stringWithFormat:@"Error moving %@ to %@: %@", item.path, destination, error.localizedDescription];
        [alert runModal];
        return;
    }

    [self populateScripts];
    NSInteger index = [_scriptItems indexOfObjectPassingTest:^BOOL(iTermScriptItem * _Nonnull item, NSUInteger idx, BOOL * _Nonnull stop) {
        return [item.path isEqual:url.path];
    }];
    if (index >= 0 && index < _scriptItems.count) {
        [_scriptsButton selectItemAtIndex:index];
        [self didSelectScriptAtIndex:index];
    }
}

- (IBAction)checkForUpdates:(id)sender {
    const NSInteger index = _tableView.selectedRow;
    if (index < 0 || !_selectedScriptItem) {
        return;
    }
    iTermScriptItem *selectedScriptItem = _selectedScriptItem;
    iTermTuple<NSString *, NSString *> *tuple = _packageTuples[_tableView.selectedRow];
    NSString *selectedDependencyName = tuple.firstObject;
    __weak __typeof(self) weakSelf = self;
    [self runPip3WithArguments:@[ @"install", selectedDependencyName, @"--upgrade" ] completion:^{
        [weakSelf pip3UpgradeDidFinish:tuple
                                 index:index
                            scriptPath:selectedScriptItem.path];
    }];
}

- (IBAction)add:(id)sender {
    iTermScriptItem *selectedScriptItem = _selectedScriptItem;
    if (!selectedScriptItem) {
        return;
    }
    NSString *newDependencyName = [self requestDependencyName];
    if (!newDependencyName) {
        return;
    }
    [self install:newDependencyName selectedScriptPath:selectedScriptItem.path completion:nil];
}

- (void)install:(NSString *)newDependencyName selectedScriptPath:(NSString *)selectedScriptPath completion:(void (^)(void))completion {
    __weak __typeof(self) weakSelf = self;
    [self runPip3WithArguments:@[ @"install", newDependencyName ] completion:^{
        [weakSelf pip3InstallDidFinish:selectedScriptPath newDependencyName:newDependencyName];
        if (completion) {
            completion();
        }
    }];
}

- (IBAction)remove:(id)sender {
    const NSInteger index = _tableView.selectedRow;
    if (index < 0) {
        return;
    }
    iTermTuple<NSString *, NSString *> *tuple = _packageTuples[_tableView.selectedRow];
    NSString *selectedDependencyName = tuple.firstObject;
    iTermScriptItem *selectedScriptItem = _selectedScriptItem;
    __weak __typeof(self) weakSelf = self;
    [self runPip3WithArguments:@[ @"uninstall", selectedDependencyName ] completion:^{
        [weakSelf pip3UninstallDidFinish:tuple index:index selectedScriptPath:selectedScriptItem.path];
    }];
}

- (IBAction)scriptDidChange:(id)sender {
    [self didSelectScriptAtIndex:_scriptsButton.selectedTag];
}

- (IBAction)closeCurrentSession:(id)sender {
    [self close];
}

- (IBAction)dismissController:(id)sender {
    [self close];
}

- (IBAction)pythonVersionChanged:(id)sender {
    NSString *selectedVersion = [[_pythonVersionButton selectedItem] title];
    if ([selectedVersion isEqualToString:_pythonVersion]) {
        return;
    }
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    if ([comparator compareVersion:selectedVersion toVersion:_pythonVersion] == NSOrderedAscending) {
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = @"You have asked to downgrade to an older Python version. Dependencies will need to be reinstalled. This may go badly. Are you sure you want to do this?";
        warning.heading = @"Confirm Python Downgrade";
        warning.actionLabels = @[ @"OK", @"Cancel" ];
        warning.identifier = @"DependencyEditorConfirmDowngrade";
        warning.warningType = kiTermWarningTypePersistent;
        warning.window = self.window;

        const iTermWarningSelection selection = [warning runModal];
        if (selection == kiTermWarningSelection1) {
            [_pythonVersionButton selectItemWithTitle:_pythonVersion];
            return;
        }
    } else {
        iTermWarning *warning = [[iTermWarning alloc] init];
        warning.title = @"You have asked to upgrade to a newer Python version. Dependencies will need to be reinstalled. OK to continue?";
        warning.heading = @"Confirm Python Upgrade";
        warning.actionLabels = @[ @"OK", @"Cancel" ];
        warning.identifier = @"DependencyEditorConfirmUpgrade";
        warning.warningType = kiTermWarningTypePersistent;
        warning.window = self.window;

        const iTermWarningSelection selection = [warning runModal];
        if (selection == kiTermWarningSelection1) {
            [_pythonVersionButton selectItemWithTitle:_pythonVersion];
            return;
        }
    }

    _pythonVersion = selectedVersion;
    NSString *path = [_selectedScriptItem.path stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:path];
    NSArray<NSString *> *dependencies = [parser.dependencies copy];
    [iTermSetupCfgParser writeSetupCfgToFile:path
                                        name:parser.name
                                dependencies:@[]
                         ensureiTerm2Present:NO
                               pythonVersion:_pythonVersion
                          environmentVersion:parser.minimumEnvironmentVersion];
    [self installPackages:dependencies selectedScriptPath:_selectedScriptItem.path];
}

- (void)installPackages:(NSArray<NSString *> *)packages selectedScriptPath:(NSString *)selectedScriptPath {
    if (packages.count == 0) {
        return;
    }
    NSString *newDependencyName = packages.firstObject;
    [self install:newDependencyName selectedScriptPath:selectedScriptPath completion:^{
        [self installPackages:[packages subarrayFromIndex:1] selectedScriptPath:selectedScriptPath];
    }];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return _packageTuples.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *const identifier = NSStringFromClass(self.class);
    NSTableCellView *view = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!view) {
        view = [[NSTableCellView alloc] init];

        NSTextField *textField = [NSTextField it_textFieldForTableViewWithIdentifier:identifier];
        textField.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
        view.textField = textField;
        [view addSubview:textField];
        textField.frame = view.bounds;
        textField.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
    }
    if ([tableColumn.identifier isEqualToString:@"package"]) {
        view.textField.stringValue = _packageTuples[row].firstObject;
    } else {
        view.textField.stringValue = _packageTuples[row].secondObject;
    }
    return view;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    const BOOL haveSelection = _tableView.selectedRow >= 0;
    _checkForUpdate.enabled = haveSelection;
    _remove.enabled = haveSelection;
}

@end
