//
//  iTermProfileModelJournal.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/20.
//

#import <Foundation/Foundation.h>

#import "iTermProfile.h"

NS_ASSUME_NONNULL_BEGIN

@class NSMenu;
@class ProfileModel;

typedef enum {
    JOURNAL_ADD,
    JOURNAL_REMOVE,
    JOURNAL_REMOVE_ALL,
    JOURNAL_SET_DEFAULT
} JournalAction;

@interface iTermProfileModelJournalParams: NSObject
@property (nonatomic) SEL selector;                  // normal action
@property (nonatomic) SEL alternateSelector;         // opt+click
@property (nonatomic) SEL openAllSelector;           // open all bookmarks
@property (nonatomic) SEL alternateOpenAllSelector;  // opt+open all bookmarks
@property (nonatomic, weak) id target;               // receiver of selector (actually an __unsafe_unretained id)
@end

@protocol iTermProfileModelMenuController<NSObject>
- (void)addBookmark:(Profile *)b
             toMenu:(NSMenu *)menu
     startingAtItem:(int)skip
           withTags:(NSArray * _Nullable)tags
             params:(iTermProfileModelJournalParams *)params
              atPos:(int)theIndex
         identifier:(NSString * _Nullable)identifier;
@end

@protocol iTermProfileModelJournalModel<NSObject>
- (Profile *)profileWithGuid:(NSString *)guid;
- (id<iTermProfileModelMenuController>)menuController;
@end

@interface BookmarkJournalEntry : NSObject

@property(nonatomic, readonly) JournalAction action;
@property(nonatomic, readonly) int index;  // Index of bookmark
@property(nullable, nonatomic, readonly, strong) NSString *guid;
@property(nonatomic, readonly, strong) id<iTermProfileModelJournalModel> model;
@property(nonatomic, readonly, strong) NSArray *tags;  // Tags before the action was applied.

+ (instancetype)journalWithAction:(JournalAction)action
                         bookmark:(nullable Profile *)bookmark
                            model:(id<iTermProfileModelJournalModel>)model
                       identifier:(NSString * _Nullable)identifier;

+ (instancetype)journalWithAction:(JournalAction)action
                         bookmark:(nullable Profile *)bookmark
                            model:(id<iTermProfileModelJournalModel>)model
                            index:(int)index
                       identifier:(NSString * _Nullable)identifier;

@end

NS_ASSUME_NONNULL_END
