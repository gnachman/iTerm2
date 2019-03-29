//
//  iTermSearchableViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearch.h"

@protocol iTermSearchableViewController<NSObject>
- (NSArray<iTermPreferencesSearchDocument *> *)searchableViewControllerDocuments;
- (void)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document;
@end

