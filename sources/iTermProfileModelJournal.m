//
//  iTermProfileModelJournal.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/20.
//

#import "iTermProfileModelJournal.h"

#import "ITAddressBookMgr.h"

@implementation iTermProfileModelJournalParams
@end

@interface BookmarkJournalEntry()
@property(nonatomic, readwrite) JournalAction action;
@property(nonatomic, readwrite) int index;
@property(nullable, nonatomic, readwrite, strong) NSString *guid;
@property(nonatomic, readwrite, strong) id<iTermProfileModelJournalModel>model;
@property(nonatomic, readwrite, strong) NSArray *tags;
@property(nullable, nonatomic, copy) NSString *identifier;
@end

@implementation BookmarkJournalEntry

+ (BookmarkJournalEntry *)journalWithAction:(JournalAction)action
                                   bookmark:(Profile *)bookmark
                                      model:(id<iTermProfileModelJournalModel>)model
                                 identifier:(NSString *)identifier {
    return [self journalWithAction:action
                          bookmark:bookmark
                             model:model
                             index:0
                        identifier:identifier];
}

+ (instancetype)journalWithAction:(JournalAction)action
                         bookmark:(Profile *)profile
                            model:(id<iTermProfileModelJournalModel>)model
                            index:(int)index
                       identifier:(NSString *)identifier {
    BookmarkJournalEntry *entry = [[BookmarkJournalEntry alloc] init];
    entry.action = action;
    entry.guid = [[profile objectForKey:KEY_GUID] copy];
    entry.model = model;
    entry.tags = [[NSArray alloc] initWithArray:[profile objectForKey:KEY_TAGS]];
    return entry;
}


@end
