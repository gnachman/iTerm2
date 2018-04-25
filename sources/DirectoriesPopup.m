//
//  DirectoriesPopup.m
//  iTerm
//
//  Created by George Nachman on 5/2/14.
//
//

#import "DirectoriesPopup.h"
#import "iTermRecentDirectoryMO.h"
#import "iTermRecentDirectoryMO+Additions.h"
#import "iTermShellHistoryController.h"
#import "NSDateFormatterExtras.h"
#import "PopupModel.h"

@implementation DirectoriesPopupEntry

- (void)dealloc {
    [_entry release];
    [super dealloc];
}

@end

@implementation DirectoriesPopupWindowController {
    __weak IBOutlet NSTableView *_tableView;
    __weak IBOutlet NSTableColumn *_mainColumn;
}

- (instancetype)init {
    self = [super initWithWindowNibName:@"DirectoriesPopup"
                               tablePtr:nil
                                  model:[[[PopupModel alloc] init] autorelease]];
    if (self) {
        [self setTableView:_tableView];
    }

    return self;
}

- (void)dealloc {
    [_tableView setDelegate:nil];
    [_tableView setDataSource:nil];
    [super dealloc];
}

- (void)loadDirectoriesForHost:(VT100RemoteHost *)host {
    [[self unfilteredModel] removeAllObjects];
    for (iTermRecentDirectoryMO *entry in [[iTermShellHistoryController sharedInstance] directoriesSortedByScoreOnHost:host]) {
        DirectoriesPopupEntry *popupEntry = [[[DirectoriesPopupEntry alloc] init] autorelease];
        popupEntry.entry = entry;
        [popupEntry setMainValue:popupEntry.entry.path];
        [[self unfilteredModel] addObject:popupEntry];
    }
    [self reloadData:YES];
}

- (id)tableView:(NSTableView *)aTableView
    objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex {
    DirectoriesPopupEntry* entry = [[self model] objectAtIndex:[self convertIndex:rowIndex]];
    if ([[aTableColumn identifier] isEqualToString:@"date"]) {
        // Date
        return [NSDateFormatter dateDifferenceStringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:entry.entry.lastUse.doubleValue]];
    } else {
        // Contents
        return [super tableView:aTableView objectValueForTableColumn:aTableColumn row:rowIndex];
    }
}

- (void)rowSelected:(id)sender {
    if ([_tableView selectedRow] >= 0) {
        DirectoriesPopupEntry* entry = [[self model] objectAtIndex:[self convertIndex:[_tableView selectedRow]]];
        [self.delegate popupInsertText:entry.entry.path];
        [super rowSelected:sender];
    }
}

- (NSAttributedString *)shrunkToFitAttributedString:(NSAttributedString *)attributedString
                                            inEntry:(DirectoriesPopupEntry *)entry
                                     baseAttributes:(NSDictionary *)baseAttributes {
    NSIndexSet *indexes =
        [[iTermShellHistoryController sharedInstance] abbreviationSafeIndexesInRecentDirectory:entry.entry];
    return [entry.entry attributedStringForTableColumn:_mainColumn
                               basedOnAttributedString:attributedString
                                        baseAttributes:baseAttributes
                            abbreviationSafeComponents:indexes];
}

- (NSString *)truncatedMainValueForEntry:(DirectoriesPopupEntry *)entry {
    // Don't allow truncation because directories shouldn't be unreasonably big.
    return entry.entry.path;
}

@end
