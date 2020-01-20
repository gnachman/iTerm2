//
//  iTermProfilesMenuController.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/20/20.
//

#import <Cocoa/Cocoa.h>

#import "iTermProfileModelJournal.h"

NS_ASSUME_NONNULL_BEGIN

@interface iTermProfilesMenuController : NSObject<iTermProfileModelMenuController>

+ (void)applyJournal:(NSDictionary *)journal
              toMenu:(NSMenu *)menu
      startingAtItem:(int)skip
              params:(iTermProfileModelJournalParams *)params;

+ (void)applyJournal:(NSDictionary *)journal
              toMenu:(NSMenu *)menu
              params:(iTermProfileModelJournalParams *)params;

- (void)addBookmark:(nullable Profile *)b
             toMenu:(NSMenu *)menu
     startingAtItem:(int)skip
           withTags:(nullable NSArray *)tags
             params:(iTermProfileModelJournalParams *)params
              atPos:(int)pos;

@end

NS_ASSUME_NONNULL_END
