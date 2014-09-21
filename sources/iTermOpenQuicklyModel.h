#import <Foundation/Foundation.h>

@class PTYSession;

@protocol iTermOpenQuicklyModelDelegate <NSObject>

// Returns an NSString or NSAttributedString for a feature with a given |name|
// and |value|. If |name| is nil then it is the feature's title. |highlight|
// gives indices that should be highlighted, and may be nil.
- (id)openQuicklyModelDisplayStringForFeatureNamed:(NSString *)name
                                             value:(NSString *)value
                                highlightedIndexes:(NSIndexSet *)highlight;

@end

@interface iTermOpenQuicklyModel : NSObject

@property(nonatomic, retain) NSMutableArray *items;
@property(nonatomic, assign) id<iTermOpenQuicklyModelDelegate> delegate;

- (void)removeAllItems;

// Recalculate items, adding those that match |queryString|.
- (void)updateWithQuery:(NSString *)queryString;

// Returns a PTYSession* or Profile* for an item at a given index. May return nil if the
// session has closed or profile was deleted.
- (id)objectAtIndex:(NSInteger)index;

@end
