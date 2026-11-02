#import <Foundation/Foundation.h>

@class PTYSession;
@protocol iTermOpenQuicklyCommand;

@protocol iTermOpenQuicklyModelDelegate <NSObject>

// Returns an NSString or NSAttributedString for a feature with a given |name|
// and |value|. If |name| is nil then it is the feature's title. |highlight|
// gives indices that should be highlighted, and may be nil.
- (id)openQuicklyModelDisplayStringForFeatureNamed:(NSString *)name
                                             value:(NSString *)value
                                highlightedIndexes:(NSIndexSet *)highlight;
- (NSAttributedString *)openQuicklyModelAttributedStringForDetail:(NSString *)detail
                                                      featureName:(NSString *)featureName;

// Called when results that are computed asynchronously (such as session contents
// matches) change after -updateWithQuery: returned. The delegate should call
// -updateWithQuery: again with the same query to pick them up.
- (void)openQuicklyModelDidChangeAsynchronously;

@end

@interface iTermOpenQuicklyModel : NSObject

@property(nonatomic, retain) NSMutableArray *items;
@property(nonatomic, assign) id<iTermOpenQuicklyModelDelegate> delegate;

// Removes all items and cancels any search in progress.
- (void)removeAllItems;

// Recalculate items, adding those that match |queryString|.
- (void)updateWithQuery:(NSString *)queryString;

// Parses a query into the command its “/x” prefix names (or no command) and
// the text that follows the prefix.
- (id<iTermOpenQuicklyCommand>)commandForQuery:(NSString *)queryString;

// Returns a PTYSession* or Profile* for an item at a given index. May return nil if the
// session has closed or profile was deleted.
- (id)objectAtIndex:(NSInteger)index;

@end
