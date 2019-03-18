//
//  iTermDependencyEditorWindowController.m
//  iTerm2
//
//  Created by George Nachman on 1/12/19.
//

#import "iTermDependencyEditorWindowController.h"

#import "DebugLogging.h"
#import "iTermController.h"
#import "iTermPythonRuntimeDownloader.h"
#import "iTermScriptsMenuController.h"
#import "iTermSetupCfgParser.h"
#import "iTermTuple.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
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
    NSMutableArray<NSString *> *_scripts;
    NSArray<iTermTuple<NSString *, NSString *> *> *_packageTuples;
    NSString *_selectedScriptPath;
    NSString *_pythonVersion;
}

+ (instancetype)sharedInstance {
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
        NSString *preferred = [_selectedScriptPath copy];
        [self reload];
        NSInteger index = [_scripts indexOfObject:preferred];
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
    if (_scripts.count) {
        [self didSelectScriptAtIndex:0];
    }
}

- (void)fetchVersionOfPackage:(NSString *)packageName completion:(void (^)(BOOL ok, NSString *result))completion {
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptPath];
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
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptPath];
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
    _selectedScriptPath = _scripts[index];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:[_scripts[index] stringByAppendingPathComponent:@"setup.cfg"]];
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
    NSString *const env = [[_selectedScriptPath stringByAppendingPathComponent:@"iterm2env"] stringByAppendingPathComponent:@"versions"];
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
    _scripts = [NSMutableArray array];
    _checkForUpdate.enabled = NO;
    _remove.enabled = NO;
    [_scriptsButton.menu removeAllItems];
    [self addScriptItems:[iTermScriptsMenuController scriptItems] breadcrumbs:@[]];
}

- (void)addScriptItems:(NSArray<iTermScriptItem *> *)scriptItems breadcrumbs:(NSArray<NSString *> *)breadcrumbs {
    for (iTermScriptItem *item in [scriptItems sortedArrayUsingComparator:^NSComparisonResult(iTermScriptItem * _Nonnull obj1, iTermScriptItem * _Nonnull obj2) {
        return [obj1.name compare:obj2.name];
    }]) {
        if (item.isFolder) {
            [self addScriptItems:item.children breadcrumbs:[breadcrumbs arrayByAddingObject:item.name]];
            continue;
        }
        if (!item.fullEnvironment) {
            continue;
        }
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[[breadcrumbs arrayByAddingObject:item.name] componentsJoinedByString:@"/"]
                                                          action:nil
                                                   keyEquivalent:@""];
        menuItem.tag = _scripts.count;
        [_scriptsButton.menu addItem:menuItem];
        [_scripts addObject:item.path];
    }
}

- (void)pip3UpgradeDidFinish:(iTermTuple<NSString *, NSString *> *)tuple index:(NSInteger)index {
    if (_packageTuples.count <= index) {
        return;
    }
    if (_packageTuples[index] == tuple) {
        [self loadPackageAtIndex:index];
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
    NSURL *container = [NSURL fileURLWithPath:_selectedScriptPath];
    NSString *pip3 = [[iTermPythonRuntimeDownloader sharedInstance] pip3At:[container.path stringByAppendingPathComponent:@"iterm2env"]
                                                             pythonVersion:_pythonVersion];
    NSArray *augmentedEscapedArgs = [[@[ pip3 ] arrayByAddingObjectsFromArray:arguments] mapWithBlock:^id(NSString *arg) {
        return [arg stringWithEscapedShellCharactersIncludingNewlines:YES];
    }];
    NSString *command = [augmentedEscapedArgs componentsJoinedByString:@" "];
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
    [[iTermController sharedInstance] openSingleUseWindowWithCommand:command
                                                              inject:nil
                                                         environment:nil
                                                          completion:^{
                                                              completion();
                                                          }];
}

- (void)pip3InstallDidFinish:(NSString *)selectedScriptPath newDependencyName:(NSString *)newDependencyName {
    if (![selectedScriptPath isEqualToString:_selectedScriptPath]) {
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
    if (![selectedScriptPath isEqualToString:_selectedScriptPath]) {
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

#pragma mark - Actions

- (IBAction)checkForUpdates:(id)sender {
    const NSInteger index = _tableView.selectedRow;
    if (index < 0) {
        return;
    }
    iTermTuple<NSString *, NSString *> *tuple = _packageTuples[_tableView.selectedRow];
    NSString *selectedDependencyName = tuple.firstObject;
    __weak __typeof(self) weakSelf = self;
    [self runPip3WithArguments:@[ @"install", selectedDependencyName, @"--upgrade" ] completion:^{
        [weakSelf pip3UpgradeDidFinish:tuple index:index];
    }];
}

- (IBAction)add:(id)sender {
    NSString *selectedScriptPath = [_selectedScriptPath copy];
    if (!selectedScriptPath) {
        return;
    }
    NSString *newDependencyName = [self requestDependencyName];
    if (!newDependencyName) {
        return;
    }
    [self install:newDependencyName selectedScriptPath:selectedScriptPath completion:nil];
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
    NSString *selectedScriptPath = [_selectedScriptPath copy];
    __weak __typeof(self) weakSelf = self;
    [self runPip3WithArguments:@[ @"uninstall", selectedDependencyName ] completion:^{
        [weakSelf pip3UninstallDidFinish:tuple index:index selectedScriptPath:selectedScriptPath];
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
    NSString *path = [_selectedScriptPath stringByAppendingPathComponent:@"setup.cfg"];
    iTermSetupCfgParser *parser = [[iTermSetupCfgParser alloc] initWithPath:path];
    NSArray<NSString *> *dependencies = [parser.dependencies copy];
    [iTermSetupCfgParser writeSetupCfgToFile:path
                                        name:parser.name
                                dependencies:@[]
                         ensureiTerm2Present:NO
                               pythonVersion:_pythonVersion
                          environmentVersion:parser.minimumEnvironmentVersion];
    NSString *selectedScriptPath = [_selectedScriptPath copy];
    [self installPackages:dependencies selectedScriptPath:selectedScriptPath];
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
