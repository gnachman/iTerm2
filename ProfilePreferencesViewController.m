//
//  ProfilePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/8/14.
//
//

#import "ProfilePreferencesViewController.h"
#import "BulkCopyProfilePreferencesWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermKeyBindingMgr.h"
#import "iTermSizeRememberingView.h"
#import "iTermWarning.h"
#import "PreferencePanel.h"
#import "ProfileListView.h"
#import "ProfilesAdvancedPreferencesViewController.h"
#import "ProfilesGeneralPreferencesViewController.h"
#import "ProfilesColorsPreferencesViewController.h"
#import "ProfilesKeysPreferencesViewController.h"
#import "ProfilesTextPreferencesViewController.h"
#import "ProfilesTerminalPreferencesViewController.h"
#import "ProfilesWindowPreferencesViewController.h"
#import "ProfilesSessionPreferencesViewController.h"

static NSString *const kRefreshProfileTable = @"kRefreshProfileTable";

@interface ProfilePreferencesViewController () <
    iTermProfilePreferencesBaseViewControllerDelegate,
    NSTabViewDelegate,
    ProfileListViewDelegate,
    ProfilesGeneralPreferencesViewControllerDelegate>
@end

@implementation ProfilePreferencesViewController {
    IBOutlet ProfileListView *_profilesListView;

    // Other actions… under list of profiles in prefs>profiles.
    IBOutlet NSPopUpButton *_otherActionsPopup;
    
    // Tab view for profiles (general/colors/text/window/terminal/session/keys/advanced)
    IBOutlet NSTabView *_tabView;
    
    // Minus under table view to delete the selected profile.
    IBOutlet NSButton *_removeProfileButton;

    // Plus under table view to add a new profile.
    IBOutlet NSButton *_addProfileButton;

    // < Tags button
    IBOutlet NSButton *_toggleTagsButton;

    // Copy current (divorced) settings to profile.
    IBOutlet NSButton *_copyToProfileButton;

    // General tab view controller
    IBOutlet ProfilesGeneralPreferencesViewController *_generalViewController;

    IBOutlet NSTabViewItem *_generalTab;
    IBOutlet NSTabViewItem *_colorsTab;
    
    // Colors tab view controller
    IBOutlet ProfilesColorsPreferencesViewController *_colorsViewController;
    
    // Text tab view controller
    IBOutlet ProfilesTextPreferencesViewController *_textViewController;

    // Window tab view controller
    IBOutlet ProfilesWindowPreferencesViewController *_windowViewController;

    // Terminal tab view controller
    IBOutlet ProfilesTerminalPreferencesViewController *_terminalViewController;

    // Sessions tab view controller
    IBOutlet ProfilesSessionPreferencesViewController *_sessionViewController;
    
    // Keys tab view controller
    IBOutlet ProfilesKeysPreferencesViewController *_keysViewController;
    
    // Advanced tab view controller
    IBOutlet ProfilesAdvancedPreferencesViewController *_advancedViewController;
}

- (id)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(refreshProfileTable)
                                                     name:kRefreshProfileTable
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadProfiles)
                                                     name:kReloadAllProfiles
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(sessionProfileDidChange:)
                                                     name:kSessionProfileDidChange
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - NSViewController

- (void)awakeFromNib {
    [_profilesListView setUnderlyingDatasource:[_delegate profilePreferencesModel]];
    
    Profile *profile = [self selectedProfile];
    if (profile) {
        _tabView.hidden = NO;
        [_otherActionsPopup setEnabled:NO];
    } else {
        [_otherActionsPopup setEnabled:YES];
        _tabView.hidden = YES;
        [_removeProfileButton setEnabled:NO];
    }
    [self refresh];
    
    if (!profile && [_profilesListView numberOfRows]) {
        [_profilesListView selectRowIndex:0];
    }

    [_generalTab setView:_generalViewController.view];
    [_colorsTab setView:_colorsViewController.view];
}

#pragma mark - APIs

- (void)refresh {
    Profile *profile = [self selectedProfile];
    if (!profile) {
        return;
    }
    
    [self updateSubviewsForProfile:profile];
    [self reloadData];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidUpdateProfileFields
                                                        object:nil
                                                      userInfo:nil];
}

- (void)layoutSubviewsForEditCurrentSessionMode {
    _profilesListView.hidden = YES;
    _otherActionsPopup.hidden = YES;
    _addProfileButton.hidden = YES;
    _removeProfileButton.hidden = YES;
    _copyToProfileButton.hidden = NO;
    _toggleTagsButton.hidden = YES;
    [_generalViewController layoutSubviewsForEditCurrentSessionMode];
    [_windowViewController layoutSubviewsForEditCurrentSessionMode];
    [_sessionViewController layoutSubviewsForEditCurrentSessionMode];
    [_advancedViewController layoutSubviewsForEditCurrentSessionMode];
    NSRect newFrame = _tabView.frame;
    newFrame.origin.x = 0;
    _tabView.frame = newFrame;
}

- (void)selectGuid:(NSString *)guid {
    [_profilesListView selectRowByGuid:guid];
}

- (void)selectFirstProfileIfNecessary {
    if (![_profilesListView selectedGuid] && [_profilesListView numberOfRows]) {
        [_profilesListView selectRowIndex:0];
    }
}

- (Profile *)selectedProfile {
    NSString *guid = [_profilesListView selectedGuid];
    ProfileModel *model = [_delegate profilePreferencesModel];
    return [model bookmarkWithGuid:guid];
}

- (NSSize)size {
    return _tabView.frame.size;
}

- (void)selectGeneralTab {
    [_tabView selectTabViewItem:_generalTab];
}

- (void)reloadProfileInProfileViewControllers {
    [[self tabViewControllers] makeObjectsPerformSelector:@selector(reloadProfile)];
}

- (void)openToProfileWithGuid:(NSString *)guid {
    [_profilesListView reloadData];
    if ([[self selectedProfile][KEY_GUID] isEqualToString:guid]) {
        [self reloadProfileInProfileViewControllers];
    } else {
        [self selectGuid:guid];
    }
    [_tabView selectTabViewItem:_generalTab];
    [self.view.window performSelector:@selector(makeFirstResponder:)
                           withObject:_generalViewController.profileNameField
                           afterDelay:0];
}

- (BOOL)importColorPresetFromFile:(NSString*)filename {
   return [_colorsViewController importColorPresetFromFile:filename];
}

- (void)changeFont:(id)fontManager {
    [_textViewController changeFont:fontManager];
}

#pragma mark - ProfileListViewDelegate

- (void)profileTableSelectionDidChange:(id)profileTable {
    [[self tabViewControllers] makeObjectsPerformSelector:@selector(willReloadProfile)];
    Profile *profile = [self selectedProfile];
    BOOL hasSelection = (profile != nil);
    
    _tabView.hidden = !hasSelection;
    _otherActionsPopup.enabled = hasSelection;
    _removeProfileButton.enabled = hasSelection && [_profilesListView numberOfRows] > 1;

    [self updateSubviewsForProfile:profile];
    if (!_tabView.isHidden) {
        // Epilogue
        [self reloadData];

        [[NSNotificationCenter defaultCenter] postNotificationName:kPreferencePanelDidUpdateProfileFields
                                                            object:nil
                                                          userInfo:nil];
    }

    [self reloadProfileInProfileViewControllers];
}

- (void)profileTableRowSelected:(id)profileTable {
    // Do nothing on double click.
}

- (NSMenu*)profileTable:(id)profileTable menuForEvent:(NSEvent*)theEvent {
    return nil;
}

- (void)profileTableFilterDidChange:(ProfileListView*)profileListView {
    _addProfileButton.enabled = ![_profilesListView searchFieldHasText];
}

- (void)profileTableTagsVisibilityDidChange:(ProfileListView *)profileListView {
    [_toggleTagsButton setTitle:profileListView.tagsVisible ? @"< Tags" : @"Tags >"];
}

#pragma mark - Private

- (BOOL)confirmProfileDeletion:(Profile *)profile {
    NSMutableString *question = [NSMutableString stringWithFormat:@"Delete profile %@?",
                                 profile[KEY_NAME]];
    if ([iTermWarning showWarningWithTitle:question
                                   actions:@[ @"Delete", @"Cancel" ]
                                identifier:@"DeleteProfile"
                               silenceable:kiTermWarningTypeTemporarilySilenceable] == kiTermWarningSelection0) {
        return YES;
    } else {
        return NO;
    }
}

- (NSArray *)tabViewControllers {
    return @[ _generalViewController,
              _colorsViewController,
              _textViewController,
              _windowViewController,
              _terminalViewController,
              _sessionViewController,
              _keysViewController,
              _advancedViewController ];
}

- (void)removeKeyMappingsReferringToGuid:(NSString*)badRef {
    for (NSString* guid in [[ProfileModel sharedInstance] guids]) {
        Profile* profile = [[ProfileModel sharedInstance] bookmarkWithGuid:guid];
        profile = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:profile];
        if (profile) {
            [[ProfileModel sharedInstance] setBookmark:profile withGuid:guid];
        }
    }
    for (NSString* guid in [[ProfileModel sessionsInstance] guids]) {
        Profile* profile = [[ProfileModel sessionsInstance] bookmarkWithGuid:guid];
        profile = [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:profile];
        if (profile) {
            [[ProfileModel sessionsInstance] setBookmark:profile withGuid:guid];
        }
    }
    [iTermKeyBindingMgr removeMappingsReferencingGuid:badRef fromBookmark:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:kKeyBindingsChangedNotification
                                                        object:nil
                                                      userInfo:nil];
}

- (void)updateSubviewsForProfile:(Profile *)profile {
    ProfileModel *model = [_delegate profilePreferencesModel];
    if ([model numberOfBookmarks] < 2 || !profile) {
        _removeProfileButton.enabled = NO;
    } else {
        _removeProfileButton.enabled = [[_profilesListView selectedGuids] count] < [model numberOfBookmarks];
    }
    _tabView.hidden = !profile;
    _otherActionsPopup.enabled = (profile != nil);
}

- (void)reloadData {
    [_profilesListView reloadData];
}

#pragma mark - Actions

- (IBAction)removeProfile:(id)sender {
    Profile *profile = [self selectedProfile];
    if ([[_delegate profilePreferencesModel] numberOfBookmarks] == 1 || !profile) {
        NSBeep();
    } else if ([self confirmProfileDeletion:profile]) {
        int lastIndex = [_profilesListView selectedRow];
        
        NSString *guid = profile[KEY_GUID];
        [self removeKeyMappingsReferringToGuid:guid];
        [[_delegate profilePreferencesModel] removeBookmarkWithGuid:guid];
        [_profilesListView reloadData];

        int toSelect = lastIndex - 1;
        if (toSelect < 0) {
            toSelect = 0;
        }
        [_profilesListView selectRowIndex:toSelect];
        
        // If a profile was deleted, update the shortcut titles that might refer to it.
        [_generalViewController updateShortcutTitles];
    }
}

- (IBAction)addProfile:(id)sender {
    NSMutableDictionary* newDict = [[[NSMutableDictionary alloc] init] autorelease];
    // Copy the default profile's settings in
    Profile* prototype = [[_delegate profilePreferencesModel] defaultBookmark];
    if (!prototype) {
        [ITAddressBookMgr setDefaultsInBookmark:newDict];
    } else {
        [newDict setValuesForKeysWithDictionary:[[_delegate profilePreferencesModel] defaultBookmark]];
    }
    newDict[KEY_NAME] = @"New Profile";
    newDict[KEY_SHORTCUT] = @"";
    NSString* guid = [ProfileModel freshGuid];
    newDict[KEY_GUID] = guid;
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove depreated attribute with side effects
    newDict[KEY_TAGS] = @[];
    newDict[KEY_BOUND_HOSTS] = @[];
    if ([[ProfileModel sharedInstance] bookmark:newDict hasTag:@"bonjour"]) {
        [newDict removeObjectForKey:KEY_BONJOUR_GROUP];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE];
        [newDict removeObjectForKey:KEY_BONJOUR_SERVICE_ADDRESS];
        newDict[KEY_COMMAND] = @"";
        newDict[KEY_INITIAL_TEXT] = @"";
        newDict[KEY_CUSTOM_COMMAND] = @"No";
        newDict[KEY_WORKING_DIRECTORY] = @"";
        newDict[KEY_CUSTOM_DIRECTORY] = @"No";
    }
    [[_delegate profilePreferencesModel] addBookmark:newDict];
    [_profilesListView reloadData];
    [_profilesListView eraseQuery];
    [_profilesListView selectRowByGuid:guid];
    [_tabView selectTabViewItem:_generalTab];
    [self.view.window makeFirstResponder:_generalViewController.profileNameField];
}

- (IBAction)toggleTags:(id)sender {
    [_profilesListView toggleTags];
}

- (IBAction)copyToProfile:(id)sender {
    Profile *sourceProfile = [self selectedProfile];
    NSString* sourceGuid = sourceProfile[KEY_GUID];
    if (!sourceGuid) {
        return;
    }
    NSString* profileGuid = [sourceProfile objectForKey:KEY_ORIGINAL_GUID];
    Profile* destination = [[ProfileModel sharedInstance] bookmarkWithGuid:profileGuid];
    // TODO: changing color presets in cmd-i causes profileGuid=null.
    if (sourceProfile && destination) {
        NSMutableDictionary* copyOfSource = [[sourceProfile mutableCopy] autorelease];
        [copyOfSource setObject:profileGuid forKey:KEY_GUID];
        [copyOfSource removeObjectForKey:KEY_ORIGINAL_GUID];
        [copyOfSource setObject:[destination objectForKey:KEY_NAME] forKey:KEY_NAME];
        [[ProfileModel sharedInstance] setBookmark:copyOfSource withGuid:profileGuid];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kReloadAllProfiles
                                                            object:nil
                                                          userInfo:nil];
        
        // Update user defaults
        [[NSUserDefaults standardUserDefaults] setObject:[[ProfileModel sharedInstance] rawData]
                                                  forKey: @"New Bookmarks"];
    }
}

- (IBAction)openCopyBookmarks:(id)sender
{
    Profile *profile = [self selectedProfile];
    BulkCopyProfilePreferencesWindowController *bulkCopyController =
        [[BulkCopyProfilePreferencesWindowController alloc] init];
    bulkCopyController.sourceGuid = profile[KEY_GUID];
    
    bulkCopyController.keysForColors = [_colorsViewController keysForBulkCopy];
    bulkCopyController.keysForText = [_textViewController keysForBulkCopy];
    bulkCopyController.keysForWindow = [_windowViewController keysForBulkCopy];
    bulkCopyController.keysForTerminal = [_terminalViewController keysForBulkCopy];
    bulkCopyController.keysForSession = [_sessionViewController keysForBulkCopy];
    bulkCopyController.keysForKeyboard = [_keysViewController keysForBulkCopy];
    bulkCopyController.keysForAdvanced = [_advancedViewController keysForBulkCopy];
    
    [NSApp beginSheet:bulkCopyController.window
       modalForWindow:self.view.window
        modalDelegate:self
       didEndSelector:@selector(bulkCopyControllerCloseSheet:returnCode:contextInfo:)
          contextInfo:bulkCopyController];
}

- (IBAction)duplicateProfile:(id)sender
{
    Profile* profile = [self selectedProfile];
    if (!profile) {
        NSBeep();
        return;
    }
    NSMutableDictionary *newProfile = [NSMutableDictionary dictionaryWithDictionary:profile];
    NSString* newName = [NSString stringWithFormat:@"Copy of %@", newProfile[KEY_NAME]];
    
    newProfile[KEY_NAME] = newName;
    newProfile[KEY_GUID] = [ProfileModel freshGuid];
    newProfile[KEY_DEFAULT_BOOKMARK] = @"No";
    newProfile[KEY_SHORTCUT] = @"";
    newProfile[KEY_BOUND_HOSTS] = @[];
    
    [[_delegate profilePreferencesModel] addBookmark:newProfile];
    [_profilesListView reloadData];
    [_profilesListView selectRowByGuid:newProfile[KEY_GUID]];
}

- (IBAction)setAsDefault:(id)sender {
    Profile *origProfile = [self selectedProfile];
    NSString* guid = origProfile[KEY_GUID];
    if (!guid) {
        NSBeep();
        return;
    }
    [[ProfileModel sharedInstance] setDefaultByGuid:guid];
}

#pragma mark - Notifications

- (void)refreshProfileTable {
    [self profileTableSelectionDidChange:_profilesListView];
}

- (void)reloadProfiles {
    [self refresh];
}

- (void)sessionProfileDidChange:(NSNotification *)notification {
    if ([[notification object] isEqual:[self selectedProfile][KEY_GUID]]) {
        [self reloadProfileInProfileViewControllers];
    }
}

#pragma mark - Sheet

- (void)bulkCopyControllerCloseSheet:(NSWindow *)sheet
                          returnCode:(int)returnCode
                         contextInfo:(BulkCopyProfilePreferencesWindowController *)bulkCopyController {
    [sheet close];
    [bulkCopyController autorelease];
}

#pragma mark - iTermProfilesPreferencesBaseViewControllerDelegate

- (Profile *)profilePreferencesCurrentProfile {
    return [self selectedProfile];
}

- (ProfileModel *)profilePreferencesCurrentModel {
    return [_delegate profilePreferencesModel];
}


#pragma mark - ProfilesGeneralPreferencesViewControllerDelegate

- (void)profilesGeneralPreferencesNameWillChange {
    [_profilesListView clearSearchField];
}

#pragma mark - NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    iTermSizeRememberingView *theView = (iTermSizeRememberingView *)[tabViewItem view];
    [theView resetToOriginalSize];
    static const CGSize kMargin = { 9, 11 };
    static const CGFloat kTabViewMinWidth = 579;
    NSSize contentSize = NSMakeSize(NSMaxX(_profilesListView.frame) + kMargin.width + MAX(kTabViewMinWidth, 11 + theView.frame.size.width + 11) + kMargin.width,
                                    kMargin.height + 9 + theView.frame.size.height + 10 + kMargin.width + 20);
    NSWindow *window = self.view.window;
    NSPoint windowTopLeft = NSMakePoint(NSMinX(window.frame), NSMaxY(window.frame));
    NSRect frame = [window frameRectForContentRect:NSMakeRect(windowTopLeft.x, 0, contentSize.width, contentSize.height)];
    frame.origin.y = windowTopLeft.y - frame.size.height;

    [window setFrame:frame display:YES];
}

@end
