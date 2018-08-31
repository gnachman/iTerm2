#import "AppDelegate.h"

#import "SolidColorView.h"

@interface AppDelegate ()

@property (assign) IBOutlet NSWindow *windowFirst;
@property (assign) IBOutlet SolidColorView *placeholderViewFirstLeft;
@property (assign) IBOutlet SolidColorView *placeholderViewFirstRight;

@property (assign) IBOutlet NSWindow *windowSecond;
@property (assign) IBOutlet SolidColorView *placeholderViewSecondLeft;
@property (assign) IBOutlet SolidColorView *placeholderViewSecondRight;

@property (assign) IBOutlet NSWindow *windowThird;
@property (assign) IBOutlet SolidColorView *placeholderViewThirdLeft;
@property (assign) IBOutlet SolidColorView *placeholderViewThirdRight;

@property (assign) IBOutlet NSWindow *windowScreenshot;
@property (assign) IBOutlet NSImageView *imageViewScreenshot;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    iTermLibController.sharedController.delegate = self;
    
    NSColor *colorLeftPlaceholder = NSColor.greenColor;
    NSColor *colorLeftTerminal = [colorLeftPlaceholder shadowWithLevel:0.9];
    
    NSColor *colorRightPlaceholder = NSColor.blueColor;
    NSColor *colorRightTerminal = [colorRightPlaceholder shadowWithLevel:0.9];
    
    self.placeholderViewFirstLeft.color = colorLeftPlaceholder;
    self.placeholderViewFirstRight.color = colorRightPlaceholder;
    
    self.placeholderViewSecondLeft.color = colorLeftPlaceholder;
    self.placeholderViewSecondRight.color = colorRightPlaceholder;
    
    self.placeholderViewThirdLeft.color = colorLeftPlaceholder;
    self.placeholderViewThirdRight.color = colorRightPlaceholder;
    
    [self createSessionInParentView:self.placeholderViewFirstLeft withName:@"Session 01" andBackgroundColor:colorLeftTerminal];
    [self createSessionInParentView:self.placeholderViewFirstRight withName:@"Session 02" andBackgroundColor:colorRightTerminal];
    
    [self createSessionInParentView:self.placeholderViewSecondLeft withName:@"Session 03" andBackgroundColor:colorLeftTerminal];
    [self createSessionInParentView:self.placeholderViewSecondRight withName:@"Session 04" andBackgroundColor:colorRightTerminal];
}

- (iTermLibSessionController*)createSessionInParentView:(NSView*)parentView withName:(NSString*)name andBackgroundColor:(NSColor*)backgroundColor
{
    NSMutableDictionary* profileTemp = iTermLibSessionController.defaultProfile.mutableCopy;
    
    [profileTemp setObject:name forKey:KEY_NAME];
    
    [profileTemp setObject:[ITAddressBookMgr encodeColor:backgroundColor] forKey:KEY_BACKGROUND_COLOR];
    
    [profileTemp setObject:@0.5f forKey:KEY_TRANSPARENCY];
    self.windowFirst.opaque = NO;
    
    Profile* profile = profileTemp.copy;
    
    iTermLibSessionController* session = [[iTermLibController sharedController] createSessionWithProfile:profile command:[ITAddressBookMgr standardLoginCommand] initialSize:parentView.bounds.size];
    
    session.view.frame = NSMakeRect(0, 0, parentView.bounds.size.width, parentView.bounds.size.height);
    session.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    
    [parentView addSubview:session.view];
    
    return session;
}

- (void)controller:(iTermLibController *)controller shouldRemoveSessionView:(iTermLibSessionController *)session
{
    NSView* sessionView = session.view;
    [sessionView removeFromSuperview];
    
    NSLog(@"Session View was removed");
}

- (void)controller:(iTermLibController *)controller sessionDidClose:(iTermLibSessionController *)session
{
    NSLog(@"Session did Close");
}

- (void)controller:(iTermLibController *)controller nameOfSession:(iTermLibSessionController *)session didChangeTo:(NSString *)newName
{
    NSLog(@"Session name changed to '%@'", newName);
}

- (IBAction)menuItemShowFindPanel_action:(id)sender
{
    [iTermLibController.sharedController.activeSession showFindPanel];
}

- (IBAction)menuItemFindCursor_action:(id)sender
{
    [iTermLibController.sharedController.activeSession findCursor];
}

- (IBAction)menuItemHighlightCursorLine_action:(id)sender
{
    NSMenuItem *menuItem = sender;
    
    iTermLibSessionController* session = iTermLibController.sharedController.activeSession;
    
    session.highlightCursorLine = !session.highlightCursorLine;
    
    menuItem.state = session.highlightCursorLine ? NSOnState : NSOffState;
}

- (IBAction)menuItemShowTimestamps_action:(id)sender
{
    NSMenuItem *menuItem = sender;
    
    iTermLibSessionController* session = iTermLibController.sharedController.activeSession;
    
    session.showTimestamps = !session.showTimestamps;
    
    menuItem.state = session.showTimestamps ? NSOnState : NSOffState;
}

- (IBAction)menuItemBroadcastInput_action:(id)sender
{
    NSMenuItem *menuItem = sender;
    
    iTermLibController.sharedController.broadcasting = !iTermLibController.sharedController.broadcasting;
    
    menuItem.state = iTermLibController.sharedController.broadcasting ? NSOnState : NSOffState;
}

- (IBAction)menuItemPaste_action:(id)sender
{
    [iTermLibController.sharedController.activeSession paste];
}

- (IBAction)menuItemPasteSlowly_action:(id)sender
{
    [iTermLibController.sharedController.activeSession pasteSlowly];
}

- (IBAction)menuItemPasteEscapingSpecialCharacters_action:(id)sender
{
    [iTermLibController.sharedController.activeSession pasteEscapingSpecialCharacters];
}

- (IBAction)menuItemPasteAdvanced_action:(id)sender
{
    [iTermLibController.sharedController.activeSession pasteAdvanced];
}

- (IBAction)menuItemClearBuffer_action:(id)sender
{
    [iTermLibController.sharedController.activeSession clearBuffer];
}

- (IBAction)menuItemClearScrollbackBuffer_action:(id)sender
{
    [iTermLibController.sharedController.activeSession clearScrollbackBuffer];
}

- (IBAction)menuItemOpenAutocomplete_action:(id)sender
{
    [iTermLibController.sharedController.activeSession openAutocomplete];
}

- (IBAction)menuItemSetMark_action:(id)sender
{
    [iTermLibController.sharedController.activeSession setMark];
}

- (IBAction)menuItemJumpToMark_action:(id)sender
{
    [iTermLibController.sharedController.activeSession jumpToMark];
}

- (IBAction)menuItemJumpToNextMark_action:(id)sender
{
    [iTermLibController.sharedController.activeSession jumpToNextMark];
}

- (IBAction)menuItemJumpToPreviousMark_action:(id)sender
{
    [iTermLibController.sharedController.activeSession jumpToPreviousMark];
}

- (IBAction)menuItemJumpToSelection_action:(id)sender
{
    [iTermLibController.sharedController.activeSession jumpToSelection];
}

- (IBAction)menuItemToggleLogging_action:(id)sender
{
    iTermLibController.sharedController.activeSession.logging = !iTermLibController.sharedController.activeSession.logging;
}

- (IBAction)menuItemSelectAll_action:(id)sender
{
    [iTermLibController.sharedController.activeSession selectAll];
}

- (IBAction)menuItemSelectOutputOfLastCommand_action:(id)sender
{
    [iTermLibController.sharedController.activeSession selectOutputOfLastCommand];
}

- (IBAction)menuItemSelectCurrentCommand_action:(id)sender
{
    [iTermLibController.sharedController.activeSession selectCurrentCommand];
}

- (IBAction)menuItemMakeTextBigger_action:(id)sender
{
    [iTermLibController.sharedController.activeSession increaseFontSize];
}

- (IBAction)menuItemMakeTextNormalSize_action:(id)sender
{
    [iTermLibController.sharedController.activeSession restoreFontSize];
}

- (IBAction)menuItemMakeTextSmaller_action:(id)sender
{
    [iTermLibController.sharedController.activeSession decreaseFontSize];
}

- (IBAction)menuItemShowAnnotations_action:(id)sender
{
    [iTermLibController.sharedController.activeSession toggleShowAnnotations];
    
    NSMenuItem* menuItem = sender;
    
    menuItem.state = iTermLibController.sharedController.activeSession.showAnnotations ? NSOnState : NSOffState;
}

- (IBAction)menuItemAddAnnotationAtCursor_action:(id)sender
{
    [iTermLibController.sharedController.activeSession addAnnotationAtCursor];
}

- (IBAction)menuItemInstallShellIntegration_action:(id)sender
{
    [iTermLibController.sharedController.activeSession tryToRunShellIntegrationInstallerWithPromptCheck:NO];
}





- (IBAction)menuItemMoveTerminalsInFirstWindowToThirdWindow_action:(id)sender
{
    NSView* sessionViewFirstLeft = self.placeholderViewFirstLeft.subviews[0];
    NSView* sessionViewFirstRight = self.placeholderViewFirstRight.subviews[0];
    
    [sessionViewFirstLeft removeFromSuperview];
    
    [self.placeholderViewThirdLeft addSubview:sessionViewFirstLeft];
    sessionViewFirstLeft.frame = self.placeholderViewThirdLeft.bounds;
    
    [sessionViewFirstRight removeFromSuperview];
    
    [self.placeholderViewThirdRight addSubview:sessionViewFirstRight];
    sessionViewFirstRight.frame = self.placeholderViewThirdRight.bounds;
    
    [self.windowFirst close];
    
    [self.windowThird makeKeyAndOrderFront:self];
}

- (IBAction)menuItemTakeScreenshot_action:(id)sender
{
    NSImage* screenshot = iTermLibController.sharedController.activeSession.screenshot;
    
    if (screenshot) {
        [self.windowScreenshot makeKeyAndOrderFront:self];
        self.imageViewScreenshot.image = screenshot;
    }
}

@end
