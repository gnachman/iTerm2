//
//  AdvancedWorkingDirectoryWindowController.m
//  iTerm
//
//  Created by George Nachman on 4/14/14.
//
//

#import "AdvancedWorkingDirectoryWindowController.h"
#import "ITAddressBookMgr.h"
#import "iTermProfilePreferences.h"

static const NSInteger kCustomDirectoryTag = 0;
static const NSInteger kHomeDirectoryTag = 1;
static const NSInteger kRecycleDirectoryTag = 2;

@implementation AdvancedWorkingDirectoryWindowController {
    // Advanced working dir sheet
    IBOutlet NSMatrix* _windowDirectoryType;
    IBOutlet NSTextField* _windowDirectory;
    IBOutlet NSMatrix* _tabDirectoryType;
    IBOutlet NSTextField* _tabDirectory;
    IBOutlet NSMatrix* _paneDirectoryType;
    IBOutlet NSTextField* _paneDirectory;
}

- (instancetype)init {
    return [super initWithWindowNibName:@"AdvancedWorkingDirectoryWindow"];
}

- (void)dealloc {
    [_profile release];
    [super dealloc];
}

- (NSArray<NSString *> *)allKeys {
    return @[ KEY_AWDS_WIN_OPTION,
              KEY_AWDS_WIN_DIRECTORY,
              KEY_AWDS_TAB_OPTION,
              KEY_AWDS_TAB_DIRECTORY,
              KEY_AWDS_PANE_OPTION,
              KEY_AWDS_PANE_DIRECTORY ];
}

#pragma mark - Actions

- (IBAction)ok:(id)sender {
    NSMutableDictionary *dict = [[_profile mutableCopy] autorelease];
    
    dict[KEY_AWDS_WIN_OPTION] = [self valueForTag:_windowDirectoryType.selectedTag];
    dict[KEY_AWDS_TAB_OPTION] = [self valueForTag:_tabDirectoryType.selectedTag];
    dict[KEY_AWDS_PANE_OPTION] = [self valueForTag:_paneDirectoryType.selectedTag];
    
    dict[KEY_AWDS_WIN_DIRECTORY] = [_windowDirectory stringValue];
    dict[KEY_AWDS_TAB_DIRECTORY] = [_tabDirectory stringValue];
    dict[KEY_AWDS_PANE_DIRECTORY] = [_paneDirectory stringValue];
    
    self.profile = dict;
    [NSApp endSheet:self.window];
}

#pragma mark - Private

- (void)setAdvancedBookmarkMatrix:(NSMatrix *)matrix withValue:(NSString *)value {
    if ([value isEqualToString:kProfilePreferenceInitialDirectoryCustomValue]) {
        [matrix selectCellWithTag:kCustomDirectoryTag];
    } else if ([value isEqualToString:kProfilePreferenceInitialDirectoryRecycleValue]) {
        [matrix selectCellWithTag:kRecycleDirectoryTag];
    } else {
        [matrix selectCellWithTag:kHomeDirectoryTag];
    }
}

- (void)safelySetStringValue:(NSString *)value in:(NSTextField *)field {
    [field setStringValue:value ?: @""];
}

- (NSString *)valueForTag:(NSInteger)tag {
    switch (tag) {
        case kCustomDirectoryTag:
            return kProfilePreferenceInitialDirectoryCustomValue;
            
        case kRecycleDirectoryTag:
            return kProfilePreferenceInitialDirectoryRecycleValue;

        case kHomeDirectoryTag:
        default:
            return kProfilePreferenceInitialDirectoryHomeValue;
            
   }
}

- (void)setProfile:(NSDictionary *)profile {
    [_profile autorelease];
    _profile = [profile copy];
    [self setAdvancedBookmarkMatrix:_windowDirectoryType
                          withValue:[_profile objectForKey:KEY_AWDS_WIN_OPTION]];
    [self safelySetStringValue:[_profile objectForKey:KEY_AWDS_WIN_DIRECTORY]
                            in:_windowDirectory];
    
    [self setAdvancedBookmarkMatrix:_tabDirectoryType
                          withValue:[_profile objectForKey:KEY_AWDS_TAB_OPTION]];
    [self safelySetStringValue:[_profile objectForKey:KEY_AWDS_TAB_DIRECTORY]
                            in:_tabDirectory];
    
    [self setAdvancedBookmarkMatrix:_paneDirectoryType
                          withValue:[_profile objectForKey:KEY_AWDS_PANE_OPTION]];
    [self safelySetStringValue:[_profile objectForKey:KEY_AWDS_PANE_DIRECTORY]
                            in:_paneDirectory];
}

@end
