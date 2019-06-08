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
#import "iTermDynamicProfileManager.h"
#import "iTermFlippedView.h"
#import "iTermKeyBindingMgr.h"
#import "iTermProfilePreferences.h"
#import "iTermProfilePreferencesTabViewWrapperView.h"
#import "iTermSizeRememberingView.h"
#import "iTermVariableScope.h"
#import "iTermWarning.h"
#import "NSArray+iTerm.h"
#import "NSDictionary+iTerm.h"
#import "NSDictionary+Profile.h"
#import "NSJSONSerialization+iTerm.h"
#import "NSObject+iTerm.h"
#import "NSView+iTerm.h"
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

@interface NSWindow(LazyHacks)
- (void)safeMakeFirstResponder:(id)view;
@end

@implementation NSWindow(LazyHacks)

- (void)safeMakeFirstResponder:(NSView *)view {
    if (view.window == self) {
        [self makeFirstResponder:view];
    }
}

@end

static const CGFloat kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode = 7;
static const CGFloat kSideMarginsWithinInnerTabView = 11;
NSString *const kProfileSessionNameDidEndEditing = @"kProfileSessionNameDidEndEditing";
NSString *const kProfileSessionHotkeyDidChange = @"kProfileSessionHotkeyDidChange";

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
    IBOutlet iTermProfilePreferencesTabViewWrapperView *_tabViewWrapperView;

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

    BulkCopyProfilePreferencesWindowController *_bulkCopyController;
    NSRect _desiredFrame;
    BOOL _needsWarning;
}

- (instancetype)init {
    self = [super init];
    if (self) {
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
    _profilesListView.delegate = nil;
}

#pragma mark - iTermPreferencesBaseViewController

- (void)setPreferencePanel:(NSWindowController *)preferencePanel {
    for (iTermPreferencesBaseViewController *viewController in [self tabViewControllers]) {
        viewController.preferencePanel = preferencePanel;
    }
    [super setPreferencePanel:preferencePanel];
}

- (void)windowWillClose {
    [_profilesListView unlockSelection];
}

#pragma mark - NSViewController

- (NSArray *)tabViewTuples {
    return @[ @[ _generalTab, _generalViewController.view ],
              @[ _colorsTab, _colorsViewController.view ],
              @[ _textTab, _textViewController.view ],
              @[ _windowTab, _windowViewController.view ],
              @[ _terminalTab, _terminalViewController.view ],
              @[ _sessionTab, _sessionViewController.view ],
              @[ _keysTab, _keysViewController.view ],
              @[ _advancedTab, _advancedViewController.view ] ];
}

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

    NSArray *tabViewTuples = [self tabViewTuples];
    for (NSArray *tuple in tabViewTuples) {
        NSTabViewItem *tabViewItem = tuple[0];
        NSView *view = tuple[1];

        // Maximum allowed height for a tab view item. Taller ones get a scroll view.
        static const CGFloat kMaxHeight = 492;
        if (view.frame.size.height > kMaxHeight) {
            // If the view is too tall, wrap it in a scroll view.
            NSRect theFrame = NSMakeRect(0, 0, view.frame.size.width, kMaxHeight);
            iTermSizeRememberingView *sizeRememberingView =
                [[iTermSizeRememberingView alloc] initWithFrame:theFrame];
            sizeRememberingView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            sizeRememberingView.autoresizesSubviews = YES;
            NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:theFrame];
            scrollView.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable);
            scrollView.drawsBackground = NO;
            scrollView.hasVerticalScroller = YES;
            scrollView.hasHorizontalScroller = NO;

            iTermFlippedView *flippedView =
                [[iTermFlippedView alloc] initWithFrame:view.bounds];
            [flippedView addSubview:view];
            [flippedView flipSubviews];

            [scrollView setDocumentView:flippedView];
            [sizeRememberingView addSubview:scrollView];

            [tabViewItem setView:sizeRememberingView];
        } else {
            // Replace the filler view with the real one which isn't in the view
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
    [_terminalViewController layoutSubviewsForEditCurrentSessionMode];
    [_advancedViewController layoutSubviewsForEditCurrentSessionMode];
    [_keysViewController layoutSubviewsForEditCurrentSessionMode];
    NSRect newFrame = _tabViewWrapperView.superview.bounds;
    newFrame.size.width -= 13;

    newFrame.size.height -= kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode;
    newFrame.origin.y += kExtraMarginBetweenWindowBottomAndTabViewForEditCurrentSessionMode;

    _tabViewWrapperView.frame = newFrame;
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

- (void)openToProfileWithGuidAndEditHotKey:(NSString *)guid
                                     scope:(iTermVariableScope<iTermSessionScope> *)scope {
    self.scope = scope;
    [_profilesListView reloadData];
    if ([[self selectedProfile][KEY_GUID] isEqualToString:guid]) {
        [self reloadProfileInProfileViewControllers];
    } else {
        [self selectGuid:guid];
    }
    if (!self.view.window.attachedSheet) {
        [_tabView selectTabViewItem:_keysTab];
        [_keysViewController openHotKeyPanel:nil];
    }
}

- (void)openToProfileWithGuid:(NSString *)guid
andEditComponentWithIdentifier:(NSString *)identifier
                        scope:(iTermVariableScope<iTermSessionScope> *)scope {
    self.scope = scope;
    [_profilesListView reloadData];
    if ([[self selectedProfile][KEY_GUID] isEqualToString:guid]) {
        [self reloadProfileInProfileViewControllers];
    } else {
        [self selectGuid:guid];
    }
    if (!self.view.window.attachedSheet) {
        [_tabView selectTabViewItem:_sessionTab];
        [_sessionViewController configureStatusBarComponentWithIdentifier:identifier];
    }
}

- (void)openToProfileWithGuid:(NSString *)guid
             selectGeneralTab:(BOOL)selectGeneralTab
                        scope:(iTermVariableScope<iTermSessionScope> *)scope {
    self.scope = scope;
    [_profilesListView reloadData];
    if ([[self selectedProfile][KEY_GUID] isEqualToString:guid]) {
        [self reloadProfileInProfileViewControllers];
    } else {
        [self selectGuid:guid];
    }
    if (selectGeneralTab && !self.view.window.attachedSheet) {
        [_tabView selectTabViewItem:_generalTab];
    }
    // Use safeMakeFirstResponder in case the profile name is not visible at the time it is called.
    // Prevents an annoying message threatening a crash that never comes.
    [self.view.window performSelector:@selector(safeMakeFirstResponder:)
                           withObject:_generalViewController.profileNameFieldForEditCurrentSession
                           afterDelay:0];
}

- (void)changeFont:(id)fontManager {
    [_textViewController changeFont:fontManager];
}

- (void)resizeWindowForCurrentTabAnimated:(BOOL)animated {
    [self resizeWindowForTabViewItem:_tabView.selectedTabViewItem animated:animated];
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
                               silenceable:kiTermWarningTypeTemporarilySilenceable
                                    window:self.view.window] == kiTermWarningSelection0) {
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

- (BOOL)hasViewController:(NSViewController *)viewController {
    return [self.tabViewControllers containsObject:viewController];
}

- (id<iTermSearchableViewController>)viewControllerWithOwnerIdentifier:(NSString *)ownerIdentifier {
    return [[self tabViewControllers] objectPassingTest:^BOOL(id<iTermSearchableViewController> vc, NSUInteger index, BOOL *stop) {
        return [vc.documentOwnerIdentifier isEqualToString:ownerIdentifier];
    }];
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
    [self resizeWindowForView:theView animated:animated];
}

- (void)resizeWindowForView:(iTermSizeRememberingView *)theView animated:(BOOL)animated {
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
    frame.size.width = MAX(iTermSharedPreferencePanelWindowMinimumWidth, frame.size.width);

    if (NSEqualRects(_desiredFrame, frame)) {
        return;
    }
    if (!animated) {
        _desiredFrame = NSZeroRect;
        [window setFrame:frame display:YES];
        return;
    }

    // Animated
    _desiredFrame = frame;
    NSTimeInterval duration = [window animationResizeTime:frame];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = duration;
        [window.animator setFrame:frame display:YES];
    } completionHandler:^{
        self->_desiredFrame = NSZeroRect;
        NSRect rect = frame;
        rect.size.width += 1;
        [window setFrame:rect display:YES];
        rect.size.width -= 1;
        [window setFrame:rect display:YES];
    }];
}

- (void)invalidateSavedSize {
    _desiredFrame = NSZeroRect;
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
    NSMutableDictionary* newDict = [[NSMutableDictionary alloc] init];
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
    [newDict removeObjectForKey:KEY_DEFAULT_BOOKMARK];  // remove deprecated attribute with side effects
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
    if (!sourceProfile) {
        return;
    }

    NSString* sourceGuid = sourceProfile[KEY_GUID];
    if (!sourceGuid) {
        return;
    }

    NSString* profileGuid = [_generalViewController selectedGuid];
    Profile* destination = [[ProfileModel sharedInstance] bookmarkWithGuid:profileGuid];
    if (!destination) {
        return;
    }

    NSString *title =
        [NSString stringWithFormat:@"Replace profile “%@” with the current session's settings?",
            [iTermProfilePreferences stringForKey:KEY_NAME inProfile:destination]];
    if ([iTermWarning showWarningWithTitle:title
                                   actions:@[ @"Replace", @"Cancel" ]
                                 identifier:@"NoSyncReplaceProfileWarning"
                               silenceable:kiTermWarningTypePermanentlySilenceable
                                    window:self.view.window] == kiTermWarningSelection1) {
        return;
    }

    NSMutableDictionary* copyOfSource = [sourceProfile mutableCopy];
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

- (IBAction)openCopyBookmarks:(id)sender
{
    Profile *profile = [self selectedProfile];
    _bulkCopyController =
        [[BulkCopyProfilePreferencesWindowController alloc] init];
    _bulkCopyController.sourceGuid = profile[KEY_GUID];

    _bulkCopyController.keysForColors = [_colorsViewController keysForBulkCopy];
    _bulkCopyController.keysForText = [_textViewController keysForBulkCopy];
    _bulkCopyController.keysForWindow = [_windowViewController keysForBulkCopy];
    _bulkCopyController.keysForTerminal = [_terminalViewController keysForBulkCopy];
    _bulkCopyController.keysForSession = [_sessionViewController keysForBulkCopy];
    _bulkCopyController.keysForKeyboard = [_keysViewController keysForBulkCopy];
    _bulkCopyController.keysForAdvanced = [_advancedViewController keysForBulkCopy];

    __weak __typeof(self) weakSelf = self;
    [self.view.window beginSheet:_bulkCopyController.window completionHandler:^(NSModalResponse returnCode) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf->_bulkCopyController.window close];
        [[strongSelf.delegate profilePreferencesModel] flush];
    }];
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
    newProfile[KEY_TAGS] = [newProfile[KEY_TAGS] arrayByRemovingObject:kProfileDynamicTag];
    newProfile[KEY_HAS_HOTKEY] = @NO;  // Don't create another hotkey window with the same hotkey
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
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:[profile it_jsonSafeValue]
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];

    if (jsonData) {
        return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    } else {
        return nil;
    }
}

- (IBAction)copyAllProfilesJson:(id)sender {
    ProfileModel *model = [_delegate profilePreferencesModel];
    NSMutableString *profiles = [@"{\n\"Profiles\": [\n" mutableCopy];
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
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Error";
        alert.informativeText = @"An error occurred. Check Console.app for details.";
        [alert runModal];
    }
}

- (IBAction)importJSONProfiles:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    // Set options.
    openPanel.canChooseFiles = YES;
    openPanel.canChooseDirectories = NO;
    openPanel.allowsMultipleSelection = YES;
    openPanel.allowedFileTypes = @[ @"json" ];

    if ([openPanel runModal] == NSModalResponseOK) {
        for (NSURL *url in openPanel.URLs) {
            NSError *error = nil;
            if (![self tryToImportJSONProfileFromURL:url error:&error]) {
                NSArray<NSString *> *actions = @[ @"OK" ];
                if (![url isEqual:openPanel.URLs.lastObject]) {
                    actions = [actions arrayByAddingObject:@"Abort"];
                }
                iTermWarningSelection selection =
                    [iTermWarning showWarningWithTitle:[NSString stringWithFormat:@"Import from %@ failed: %@", url.path, error.localizedDescription]
                                               actions:actions
                                             accessory:nil
                                            identifier:@"NoSyncJSONImportFailed"
                                           silenceable:kiTermWarningTypeTemporarilySilenceable
                                               heading:@"Could not Import Profile"
                                                window:self.view.window];
                if (selection == kiTermWarningSelection1) {
                    return;
                }
            }
        }
    }
}

- (BOOL)tryToImportJSONProfileFromURL:(NSURL *)url error:(out NSError **)error {
    DLog(@"Import profile from %@", url.path);
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) {
        return NO;
    }

    id object = [NSJSONSerialization JSONObjectWithData:data
                                           options:NSJSONReadingAllowFragments
                                             error:error];
    if (!object) {
        return NO;
    }

    NSDictionary *dict = [NSDictionary castFrom:object];
    if (!dict) {
        if (error) {
            *error = [[NSError alloc] initWithDomain:@"com.iterm2.json-import-profile" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid JSON: does not have a top-level dictionary." }];
        }
        return NO;
    }

    NSString *name = dict[KEY_NAME];
    NSString *guid = dict[KEY_GUID];
    if (!name || !guid) {
        NSArray *profiles = [NSArray castFrom:dict[@"Profiles"]];
        if (profiles) {
            return [self tryToImportMultipleProfilesFromJSONObject:profiles error:error];
        }
        if (error) {
            *error = [[NSError alloc] initWithDomain:@"com.iterm2.json-import-profile" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid JSON: missing Name or Guid key in top-level dictionary." }];
        }
        return NO;
    }

    if ([[ProfileModel sharedInstance] bookmarkWithGuid:guid]) {
        dict = [dict dictionaryBySettingObject:[[NSUUID UUID] UUIDString] forKey:KEY_GUID];
    }

    [[ProfileModel sharedInstance] addBookmark:dict];
    return YES;
}

- (BOOL)tryToImportMultipleProfilesFromJSONObject:(NSArray *)profiles error:(out NSError **)error {
    NSMutableArray<NSDictionary *> *dicts = [NSMutableArray array];
    __block BOOL ok = YES;
    __block NSError *internalError = nil;
    [profiles enumerateObjectsUsingBlock:^(id  _Nonnull object, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *dict = [NSDictionary castFrom:object];
        if (!dict) {
            internalError = [[NSError alloc] initWithDomain:@"com.iterm2.json-import-profile" code:0 userInfo:@{ NSLocalizedDescriptionKey: @"Invalid JSON: not an array of dictionaries." }];
            ok = NO;
            *stop = YES;
            return;
        }

        NSString *name = dict[KEY_NAME];
        NSString *guid = dict[KEY_GUID];
        if (!name || !guid) {
            NSString *reason = [NSString stringWithFormat:@"Invalid JSON: missing Name or Guid key in profile number %@.", @(idx + 1)];
            internalError = [[NSError alloc] initWithDomain:@"com.iterm2.json-import-profile" code:0 userInfo:@{ NSLocalizedDescriptionKey: reason }];
            ok = NO;
            *stop = YES;
            return;
        }

        if ([[ProfileModel sharedInstance] bookmarkWithGuid:guid]) {
            dict = [dict dictionaryBySettingObject:[[NSUUID UUID] UUIDString] forKey:KEY_GUID];
        }

        [dicts addObject:dict];
    }];
    if (!ok) {
        if (error && internalError) {
            *error = internalError;
        }
        return NO;
    }
    for (NSDictionary *dict in dicts) {
        [[ProfileModel sharedInstance] addBookmark:dict];
    }
    return YES;
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
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Error";
        alert.informativeText = [NSString stringWithFormat:@"Couldn't convert profile to JSON: %@",
                                 [error localizedDescription]];
        [alert runModal];
    }
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [self refresh];
}

- (void)sessionProfileDidChange:(NSNotification *)notification {
    if ([[notification object] isEqual:[self selectedProfile][KEY_GUID]]) {
        [self reloadProfileInProfileViewControllers];
    }
}

#pragma mark - iTermProfilesPreferencesBaseViewControllerDelegate

- (BOOL)profilePreferencesRevealViewController:(iTermProfilePreferencesBaseViewController *)viewController {
    for (NSArray *tuple in [self tabViewTuples]) {
        NSTabViewItem *item = tuple[0];
        NSView *view = tuple[1];
        if (viewController.view == view) {
            BOOL changing = item != _tabView.selectedTabViewItem;
            [_tabView selectTabViewItem:item];
            return changing;
        }
    }
    return NO;
}

- (Profile *)profilePreferencesCurrentProfile {
    return [self selectedProfile];
}

- (ProfileModel *)profilePreferencesCurrentModel {
    return [_delegate profilePreferencesModel];
}

- (void)profilePreferencesContentViewSizeDidChange:(iTermSizeRememberingView *)view {
    if (_tabView.selectedTabViewItem.view == view ){
        [self resizeWindowForView:view animated:YES];
    }
}

- (BOOL)editingTmuxSession {
    return _tmuxSession;
}

- (void)profilePreferencesViewController:(iTermProfilePreferencesBaseViewController *)viewController
                    willSetObjectWithKey:(NSString *)key {
    if (_needsWarning) {
        return;
    }
    _needsWarning = YES;
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf showWarningIfNeeded];
    });
}

- (void)showWarningIfNeeded {
    if (!_needsWarning) {
        return;
    }
    _needsWarning = NO;
    
    Profile *profile = [self selectedProfile];
    NSString *guid = [NSString castFrom:[profile objectForKey:KEY_GUID]];
    if (!guid) {
        return;
    }
    NSArray *tagsArray = [NSArray castFrom:[profile objectForKey:KEY_TAGS]];
    if (![tagsArray containsObject:kProfileDynamicTag]) {
        return;
    }
    NSString *profileName = [profile objectForKey:KEY_NAME] ?: @"(unknown name)";
    NSString *message = [NSString stringWithFormat:@"The selected profile, “%@”, is a dynamic profile. Changes made through preferences will be lost when you restart iTerm2. To modify this profile you must edit its source file.", profileName];
    const iTermWarningSelection selection =
    [iTermWarning showWarningWithTitle:message
                               actions:@[ @"OK", @"Reveal in Finder" ]
                             accessory:nil
                            identifier:@"NoSyncDynamicProfileChangeWillBeLost"
                           silenceable:kiTermWarningTypeTemporarilySilenceable
                               heading:@"Changes Will Be Lost"
                                window:self.view.window];
    if (selection == kiTermWarningSelection0) {
        return;
    }

    [[iTermDynamicProfileManager sharedInstance] revealProfileWithGUID:guid];
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

- (void)profilesGeneralPreferencesSessionHotkeyDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:kProfileSessionHotkeyDidChange
                                                        object:[_profilesListView selectedGuid]];
}

- (iTermVariableScope<iTermSessionScope> *)profilesGeneralPreferencesScope {
    return self.scope;
}

#pragma mark - NSTabViewDelegate

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
    [self resizeWindowForTabViewItem:tabViewItem animated:YES];
}

#pragma mark - iTermSearchableViewController

- (NSArray<iTermPreferencesSearchDocument *> *)searchableViewControllerDocuments {
    return [[[self tabViewControllers] mapWithBlock:^id(id<iTermSearchableViewController> vc) {
        return [vc searchableViewControllerDocuments];
    }] flattenedArray];
}

- (void)revealControl:(NSControl *)control {
    // Is there an inner tab container view?
    for (NSTabViewItem *item in self.tabView.tabViewItems) {
        NSView *view = item.view;
        if ([view containsDescendant:control]) {
            [self.tabView selectTabViewItem:item];
            return;
        }
    }
}

- (NSView *)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document
                                                 forQuery:(NSString *)query
                                            willChangeTab:(BOOL *)willChangeTab {
    for (id<iTermSearchableViewController> vc in [self tabViewControllers]) {
        NSView *view = [vc searchableViewControllerRevealItemForDocument:document
                                                                forQuery:query
                                                           willChangeTab:willChangeTab];
        if (view) {
            return view;
        }
    }
    return nil;
}

@end
