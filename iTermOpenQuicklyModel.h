#import <Foundation/Foundation.h>

@class PTYSession;

@interface iTermOpenQuicklyModel : NSObject

@property(nonatomic, retain) NSMutableArray *items;

- (void)removeAllItems;

// Recalculate items, adding those that match |queryString|.
- (void)updateWithQuery:(NSString *)queryString;

// Returns the session for an item at a given index. May return nil if the
// session has closed.
- (PTYSession *)sessionAtIndex:(NSInteger)index;

@end
