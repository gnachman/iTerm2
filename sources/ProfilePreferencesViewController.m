//
//  ProfilePreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/8/14.
//
//

#import "ProfilePreferencesViewController.h"
#import "BulkCopyProfilePreferencesWindowController.h"
#import "DebugLogging.h"
#import "ITAddressBookMgr.h"
#import "iTermController.h"
#import "iTermFlippedView.h"
#import "iTermKeyBindingMgr.h"
#import "iTermProfilePreferences.h"
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
static const CGFloat kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode = 7;
static const CGFloat kSideMarginsWithinInnerTabView = 11;
NSString *const kProfileSessionNameDidEndEditing = @"kProfileSessionNameDidEndEditing";

@interface ProfilePreferencesViewController () <
    iTermProfilePreferencesBaseViewControllerDelegate,
    NSTabViewDelegate,
    NSWindowDelegate,
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
    IBOutlet NSTabViewItem *_textTab;
    IBOutlet NSTabViewItem *_windowTab;
    IBOutlet NSTabViewItem *_terminalTab;
    IBOutlet NSTabViewItem *_sessionTab;
    IBOutlet NSTabViewItem *_keysTab;
    IBOutlet NSTabViewItem *_advancedTab;

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

    CGFloat _minWidth;
}

- (instancetype)init {
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(profileWasDeleted:)
                                                     name:kProfileWasDeletedNotification
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

    NSArray *tabViewTuples = @[ @[ _generalTab, _generalViewController.view ],
                                @[ _colorsTab, _colorsViewController.view ],
                                @[ _textTab, _textViewController.view ],
                                @[ _windowTab, _windowViewController.view ],
                                @[ _terminalTab, _terminalViewController.view ],
                                @[ _sessionTab, _sessionViewController.view ],
                                @[ _keysTab, _keysViewController.view ],
                                @[ _advancedTab, _advancedViewController.view ] ];
    for (NSArray *tuple in tabViewTuples) {
        NSTabViewItem *tabViewItem = tuple[0];
        NSView *view = tuple[1];

        // Maximum allowed height for a tab view item. Taller ones get a scroll view.
        static const CGFloat kMaxHeight = 438;
        if (view.frame.size.height > kMaxHeight) {
            // If the view is too tall, wrap it in a scroll view.
            NSRect theFrame = NSMakeRect(0, 0, view.frame.size.width, kMaxHeight);
            iTermSizeRememberingView *sizeRememberingView =
            [[[iTermSizeRememberingView alloc] initWithFrame:theFrame] autorelease];
            sizeRememberingView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            sizeRememberingView.autoresizesSubviews = YES;
            NSScrollView *scrollView = [[[NSScrollView alloc] initWithFrame:theFrame] autorelease];
            scrollView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            scrollView.drawsBackground = NO;
            scrollView.hasVerticalScroller = YES;
            scrollView.hasHorizontalScroller = NO;

            iTermFlippedView *flippedView =
                [[[iTermFlippedView alloc] initWithFrame:view.bounds] autorelease];
            [flippedView addSubview:view];
            [flippedView flipSubviews];

            [scrollView setDocumentView:flippedView];
            [sizeRememberingView addSubview:scrollView];

            [tabViewItem setView:sizeRememberingView];
        } else {
            // Replce the filler view with the real one which isn't in the view
            // hierarchy in the .xib file which was done to make it easier for
            // views' sizes to differ.
            [tabViewItem setView:view];
        }
    }
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
    _generalTab.view = _generalViewController.view;
    [_windowViewController layoutSubviewsForEditCurrentSessionMode];
    [_sessionViewController layoutSubviewsForEditCurrentSessionMode];
    [_advancedViewController layoutSubviewsForEditCurrentSessionMode];
    NSRect newFrame = _tabView.superview.bounds;
    newFrame.size.width -= 13;

    newFrame.size.height -= kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode;
    newFrame.origin.y += kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode;

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

- (void)openToProfileWithGuid:(NSString *)guid selectGeneralTab:(BOOL)selectGeneralTab {
    [_profilesListView reloadData];
    if ([[self selectedProfile][KEY_GUID] isEqualToString:guid]) {
        [self reloadProfileInProfileViewControllers];
    } else {
        [self selectGuid:guid];
    }
    if (selectGeneralTab && !self.view.window.attachedSheet) {
        [_tabView selectTabViewItem:_generalTab];
    }
    [self.view.window performSelector:@selector(makeFirstResponder:)
                           withObject:_generalViewController.profileNameFieldForEditCurrentSession
                           afterDelay:0];
}

- (void)changeFont:(id)fontManager {
    [_textViewController changeFont:fontManager];
}

- (void)resizeWindowForCurrentTab {
    [self resizeWindowForTabViewItem:_tabView.selectedTabViewItem animated:YES];
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

- (void)resizeWindowForTabViewItem:(NSTabViewItem *)tabViewItem animated:(BOOL)animated {
    iTermSizeRememberingView *theView = (iTermSizeRememberingView *)[tabViewItem view];

    // The window's size includes all space around the tab view, plus the tab view.
    // These variables hold the space on each side of the tab view.
    CGFloat spaceAbove = 0;
    CGFloat spaceBelow = 0;
    CGFloat spaceLeft = 0;
    CGFloat spaceRight = 0;

    // Compute the size of the tab view item.
    CGSize tabViewSize;
    CGFloat preferredWidth = kSideMarginsWithinInnerTabView + theView.originalSize.width + kSideMarginsWithinInnerTabView;
    const CGFloat kTabViewMinWidth = 579;
    tabViewSize.width = MAX(kTabViewMinWidth, preferredWidth);
    tabViewSize.height = theView.originalSize.height;

    // Compute left margin
    const CGFloat kSideMarginBetweenWindowAndTabView = 9;
    if (_profilesListView.isHidden) {
      spaceLeft = kSideMarginBetweenWindowAndTabView;
    } else {
      // Leave space the for the profiles list view on the left.
      spaceLeft = NSMaxX(_profilesListView.frame) + kSideMarginBetweenWindowAndTabView;
    }

    // Other margins are easy.
    spaceRight = kSideMarginBetweenWindowAndTabView;
    const CGFloat kDistanceFromContentTopToTabViewItemTop = 36;
    const CGFloat kDistanceFromContentBottomToWindowBottom = 16;
    spaceAbove = kDistanceFromContentTopToTabViewItemTop;
    spaceBelow = kDistanceFromContentBottomToWindowBottom;
    if (_profilesListView.isHidden) {
        spaceBelow += kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode;
    }

    // Compute the size of the content within the window.
    NSSize contentSize = NSMakeSize(spaceLeft + tabViewSize.width + spaceRight,
                                    spaceAbove + tabViewSize.height + spaceBelow);

    // Compute a window frame with the new size that preserves the top left coordinate.
    NSWindow *window = self.view.window;
    NSPoint windowTopLeft = NSMakePoint(NSMinX(window.frame), NSMaxY(window.frame));
    NSRect frame = [window frameRectForContentRect:NSMakeRect(windowTopLeft.x, 0, contentSize.width, contentSize.height)];
    frame.origin.y = windowTopLeft.y - frame.size.height;

    [window setFrame:frame display:YES animate:animated];
}

#pragma mark - Actions

- (IBAction)removeProfile:(id)sender {
    DLog(@"removeProfile called");
    Profile *profile = [self selectedProfile];
    ProfileModel *model = [_delegate profilePreferencesModel];

    if (![ITAddressBookMgr canRemoveProfile:profile fromModel:model]) {
        NSBeep();
    } else if ([self confirmProfileDeletion:profile]) {
        NSString *guid = profile[KEY_GUID];
        DLog(@"Remove profile with guid %@ named %@", guid, profile[KEY_NAME]);
        int lastIndex = [_profilesListView selectedRow];
        [ITAddressBookMgr removeProfile:profile fromModel:model];
        // profileWasDeleted: gets called by notification from within removeProfile:fromModel:.
        int toSelect = lastIndex - 1;
        if (toSelect < 0) {
            toSelect = 0;
        }
        [_profilesListView selectRowIndex:toSelect];
    }
}

- (void)profileWasDeleted:(NSNotification *)notification {
    DLog(@"A profile was deleted.");
    if ([_profilesListView selectedRow] == -1) {
        [_profilesListView selectRowIndex:0];
    }
    // If a profile was deleted, update the shortcut titles that might refer to it.
    [_generalViewController updateShortcutTitles];
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
        newDict[KEY_COMMAND_LINE] = @"";
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
    NSString *title =
        [NSString stringWithFormat:@"Replace profile “%@” with the current session's settings?",
            [iTermProfilePreferences stringForKey:KEY_NAME inProfile:sourceProfile]];
    if ([iTermWarning showWarningWithTitle:title
                                   actions:@[ @"Replace", @"Cancel" ]
                                 identifier:@"NoSyncReplaceProfileWarning"
                               silenceable:kiTermWarningTypePermanentlySilenceable] == kiTermWarningSelection1) {
        return;
    }
    NSString* sourceGuid = sourceProfile[KEY_GUID];
    if (!sourceGuid) {
        return;
    }
    NSString* profileGuid = [_generalViewController selectedGuid];
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

- (NSString *)jsonForProfile:(Profile *)profile error:(NSError **)error {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:profile
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];

    if (jsonData) {
        return [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
    } else {
        return nil;
    }
}

- (IBAction)copyAllProfilesJson:(id)sender {
    ProfileModel *model = [_delegate profilePreferencesModel];
    NSMutableString *profiles = [[@"{\n\"Profiles\": [\n" mutableCopy] autorelease];
    BOOL first = YES;
    int errors = 0;
    for (Profile *profile in [model bookmarks]) {
        NSError *error = nil;
        NSString *json = [self jsonForProfile:profile error:&error];
        if (json) {
            if (first) {
                first = NO;
            } else {
                [profiles appendString:@",\n"];
            }
            [profiles appendString:json];
        } else {
            errors++;
            NSLog(@"Couldn't convert profile %@ to JSON: %@",
                  profile[KEY_NAME], [error localizedDescription]);
        }
    }
    [profiles appendString:@"\n]\n}\n"];

    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard writeObjects:@[ profiles ]];

    if (errors) {
        [NSAlert alertWithMessageText:@"Error"
                        defaultButton:@"Ok"
                      alternateButton:nil
                          otherButton:nil
            informativeTextWithFormat:@"An error occurred. Check Console.app for details."];
    }
}

- (IBAction)copyProfileJson:(id)sender {
    NSDictionary* profile = [self selectedProfile];
    if (!profile) {
        NSBeep();
        return;
    }
    NSError *error = nil;
    NSString *string = [self jsonForProfile:profile error:&error];

    if (string) {
        NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard writeObjects:@[ string ]];
    } else {
        [NSAlert alertWithMessageText:@"Error"
                        defaultButton:@"Ok"
                      alternateButton:nil
                          otherButton:nil
            informativeTextWithFormat:@"Couldn't convert profile to JSON: %@",
                                      [error localizedDescription]];
    }
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
    [[_delegate profilePreferencesModel] flush];
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
    [_profilesListView lockSelection];
}

- (void)profilesGeneralPreferencesNameDidChange {
    [_profilesListView selectLockedSelection];
}

- (void)profilesGeneralPreferencesNameDidEndEditing {
    [[NSNotificationCenter defaultCenter] postNotificationName:kProfileSessionNameDidEndEditing
                                                        object:[_profilesListView selectedGuid]];
}

#pragma mark - NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [self resizeWindowForTabViewItem:tabViewItem animated:YES];
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    [_generalViewController windowWillClose];
    [_profilesListView unlockSelection];
}

@end
