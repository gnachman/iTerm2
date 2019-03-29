//
//  iTermSearchableViewController.h
//  iTerm2
//
//  Created by George Nachman on 3/28/19.
//

#import "iTermPreferencesSearch.h"

@protocol iTermSearchableViewController<NSObject>
- (NSString *)documentOwnerIdentifier;
- (NSArray<iTermPreferencesSearchDocument *> *)searchableViewControllerDocuments;
- (NSView *)searchableViewControllerRevealItemForDocument:(iTermPreferencesSearchDocument *)document
                                                 forQuery:(NSString *)query
                                            willChangeTab:(BOOL *)willChangeTab;
@end

