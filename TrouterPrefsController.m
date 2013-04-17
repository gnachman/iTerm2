//
//  TrouterPrefsController.m
//  iTerm
//
//  Created by George Nachman on 9/28/11.
//  Copyright 2011 Georgetech. All rights reserved.
//

#import "TrouterPrefsController.h"
#import "ProfileModel.h"
#import "ITAddressBookMgr.h"
#import "PreferencePanel.h"

NSString *kTrouterActionKey = @"action";
NSString *kTrouterEditorKey = @"editor";
NSString *kTrouterTextKey = @"text";

NSString *kSublimeText2Identifier = @"com.sublimetext.2";
NSString *kSublimeText3Identifier = @"com.sublimetext.3";
NSString *kMacVimIdentifier = @"org.vim.MacVim";
NSString *kTextmateIdentifier = @"com.macromates.textmate";
NSString *kTextmate2Identifier = @"com.macromates.textmate.preview";
NSString *kBBEditIdentifier = @"com.barebones.bbedit";
    
NSString *kTrouterBestEditorAction = @"best editor";
NSString *kTrouterUrlAction = @"url";
NSString *kTrouterEditorAction = @"editor";
NSString *kTrouterCommandAction = @"command";
NSString *kTrouterRawCommandAction = @"raw command";

@implementation TrouterPrefsController

enum {
    kSublimeText2Tag = 1,
    kMacVimTag,
    kTextmateTag,
    kBBEditTag,
    kSublimeText3Tag
    // Only append to the end of the list; never delete or change.
};

@synthesize guid = guid_;

+ (NSDictionary *)defaultPrefs
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            kTrouterBestEditorAction, kTrouterActionKey,
            nil];
}

- (void)dealloc
{
    [guid_ release];
    [super dealloc];
}

+ (BOOL)applicationExists:(NSString *)bundle_id
{
    CFURLRef appURL = nil;
    OSStatus result = LSFindApplicationForInfo(kLSUnknownCreator,
                                               (CFStringRef)bundle_id,
                                               NULL,
                                               NULL,
                                               &appURL);
    
    if (appURL) {
        CFRelease(appURL);
    }
    
    switch (result) {
        case noErr:
            if ([bundle_id isEqualToString:kSublimeText2Identifier] ||
                [bundle_id isEqualToString:kSublimeText3Identifier]) {
                // Extra check for sublime text.
                if (![[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:bundle_id]) {
                    return NO;
                } else {
                    return YES;
                }
            } else {
                return YES;
            }
        case kLSApplicationNotFoundErr:
            return NO;
        default:
            return NO;
    }
}

+ (NSString *)schemeForEditor:(NSString *)editor
{
    if ([editor isEqualToString:kSublimeText2Identifier] ||
        [editor isEqualToString:kSublimeText3Identifier]) {
        return @"subl";
    }
    if ([editor isEqualToString:kMacVimIdentifier]) {
        return @"mvim";
    }
    if ([editor isEqualToString:kTextmateIdentifier]) {
        return @"txmt";
    }
    if ([editor isEqualToString:kBBEditIdentifier]) {
        return @"txmt";
    }
    return nil;
}

+ (NSString *)bestEditor
{
    if ([TrouterPrefsController applicationExists:kSublimeText3Identifier]) {
        return kSublimeText3Identifier;
    }
    if ([TrouterPrefsController applicationExists:kSublimeText2Identifier]) {
        return kSublimeText2Identifier;
    }
    if ([TrouterPrefsController applicationExists:kMacVimIdentifier]) {
        return kMacVimIdentifier;
    }
    if ([TrouterPrefsController applicationExists:kTextmateIdentifier] ||
        [TrouterPrefsController applicationExists:kTextmate2Identifier]) {
        return kTextmateIdentifier;
    }
    if ([TrouterPrefsController applicationExists:kBBEditIdentifier]) {
        return kBBEditIdentifier;
    }
    return nil;
}

- (void)awakeFromNib
{
    [editors_ addItemWithTitle:@"Sublime Text 3"];
    [editors_ setAutoenablesItems:NO];
    [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setTag:kSublimeText3Tag];
    if (![TrouterPrefsController applicationExists:kSublimeText3Identifier]) {
        [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setEnabled:NO];
    }
    [editors_ addItemWithTitle:@"Sublime Text 2"];
    [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setTag:kSublimeText2Tag];
    if (![TrouterPrefsController applicationExists:kSublimeText2Identifier]) {
        [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setEnabled:NO];
    }
    [editors_ addItemWithTitle:@"MacVim"];
    [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setTag:kMacVimTag];
    if (![TrouterPrefsController applicationExists:kMacVimIdentifier]) {
        [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setEnabled:NO];
    }
    [editors_ addItemWithTitle:@"Textmate"];
    [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setTag:kTextmateTag];
    if (![TrouterPrefsController applicationExists:kTextmateIdentifier] &&
        ![TrouterPrefsController applicationExists:kTextmate2Identifier]) {
        [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setEnabled:NO];
    }
    [editors_ addItemWithTitle:@"BBEdit"];
    [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setTag:kBBEditTag];
    if (![TrouterPrefsController applicationExists:kBBEditIdentifier]) {
        [(NSMenuItem *)[[[editors_ menu] itemArray] lastObject] setEnabled:NO];
    }
    [self actionChanged:nil];
}

- (NSString *)actionIdentifier
{
    switch ([[action_ selectedItem] tag]) {
        case 1:
            return kTrouterBestEditorAction;
            
        case 2:
            return kTrouterUrlAction;
            break;
            
        case 3:
            return kTrouterEditorAction;
            break;
            
        case 4:
            return kTrouterCommandAction;
            break;
            
        case 5:
            return kTrouterRawCommandAction;
            break;
    }
    return nil;
}

- (NSString *)editorIdentifier
{
    switch ([[editors_ selectedItem] tag]) {
        case kSublimeText3Tag:
            return kSublimeText3Identifier;
            
        case kSublimeText2Tag:
            return kSublimeText2Identifier;
            
        case kMacVimTag:
            return kMacVimIdentifier;
            
        case kTextmateTag:
            return kTextmateIdentifier;

        case kBBEditTag:
            return kBBEditIdentifier;
    }
    return nil;
}

- (IBAction)actionChanged:(id)sender
{
    [text_ setHidden:YES];
    [editors_ setHidden:YES];
    switch ([[action_ selectedItem] tag]) {
        case 1:
            [caveat_ setStringValue:@"When you activate Semantic History on a filename, the associated app loads the file."];
            [caveat_ setHidden:NO];
            break;
            
        case 2:
            [[text_ cell] setPlaceholderString:@"Enter URL."];
            [caveat_ setStringValue:@"When you activate Semantic History on a filename, the browser opens a URL.\nUse \\1 for the filename you clicked on and \\2 for the line number."];
            [caveat_ setHidden:NO];
            [text_ setHidden:NO];
            break;
            
        case 3:
            [editors_ setHidden:NO];
            [caveat_ setStringValue:@"When you activate Semantic History on a text file, the specified editor opens it.\nOther kinds of files will be opened with their default apps."];
            [caveat_ setHidden:NO];
            break;

        case 4:
            [[text_ cell] setPlaceholderString:@"Enter command"];
            [caveat_ setStringValue:@"Command runs when you activate Semantic History on any filename.\nUse \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd."];
            [caveat_ setHidden:NO];
            [text_ setHidden:NO];
            break;

        case 5:
            [[text_ cell] setPlaceholderString:@"Enter command"];
            [caveat_ setStringValue:@"Command runs when you activate Semantic History on any text (even if it's not a valid filename).\nUse \\1 for filename, \\2 for line number, \\3 for text before click, \\4 for text after click, \\5 for pwd."];
            [caveat_ setHidden:NO];
            [text_ setHidden:NO];
            break;
    }
    if (sender) {
        if (![text_ isHidden]) {
            NSString *stringValue = [[self prefs] objectForKey:kTrouterTextKey];
            [text_ setStringValue:stringValue ? stringValue : @""];
        }
        [[PreferencePanel sharedInstance] bookmarkSettingChanged:nil];
    }
}

- (NSDictionary *)prefs
{
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [self actionIdentifier], kTrouterActionKey,
            [text_ stringValue], kTrouterTextKey,
            [self editorIdentifier], kTrouterEditorKey,
            nil];
}

- (void)setGuid:(NSString *)guid
{
    [guid_ autorelease];
    guid_ = [guid copy];
    Profile* bookmark = [[ProfileModel sharedInstance] bookmarkWithGuid:self.guid];
    NSDictionary *prefs = [bookmark objectForKey:KEY_TROUTER];
    prefs = prefs ? prefs : [TrouterPrefsController defaultPrefs];
    NSString *action = [prefs objectForKey:kTrouterActionKey];
    // Uncheck all items
    for (NSMenuItem *item in [[action_ menu] itemArray]) {
        [item setState:NSOffState];
    }
    // Set selection in menu
    if ([action isEqualToString:kTrouterBestEditorAction]) {
        [action_ selectItemWithTag:1];
    }
    if ([action isEqualToString:kTrouterUrlAction]) {
        [action_ selectItemWithTag:2];
    }
    if ([action isEqualToString:kTrouterEditorAction]) {
        [action_ selectItemWithTag:3];
    }
    if ([action isEqualToString:kTrouterCommandAction]) {
        [action_ selectItemWithTag:4];
    }
    if ([action isEqualToString:kTrouterRawCommandAction]) {
        [action_ selectItemWithTag:5];
    }
    // Check selected item
    [[[action_ menu] itemWithTag:[action_ selectedTag]] setState:NSOnState];
    [self actionChanged:nil];
    NSString *text = [prefs objectForKey:kTrouterTextKey];
    if (text) {
        [text_ setStringValue:text];
    } else {
        [text_ setStringValue:@""];
    }
    NSString *editor = [prefs objectForKey:kTrouterEditorKey];
    if ([editor isEqualToString:kSublimeText2Identifier]) {
        [editors_ selectItemWithTag:kSublimeText2Tag];
    } else if ([editor isEqualToString:kSublimeText3Identifier]) {
        [editors_ selectItemWithTag:kSublimeText3Tag];
    } else if ([editor isEqualToString:kMacVimIdentifier]) {
        [editors_ selectItemWithTag:kMacVimTag];
    } else if ([editor isEqualToString:kTextmateIdentifier]) {
        [editors_ selectItemWithTag:kTextmateTag];
    } else if ([editor isEqualToString:kBBEditIdentifier]) {
        [editors_ selectItemWithTag:kBBEditTag];
    }
}
         
@end
