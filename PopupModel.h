//
//  PopupModel.h
//  iTerm
//
//  Created by George Nachman on 12/27/13.
//
//

#import <Foundation/Foundation.h>

@class PopupEntry;

@interface PopupModel : NSObject

- (id)init;
- (id)initWithMaxEntries:(int)maxEntries;
- (void)dealloc;
- (NSUInteger)count;
- (void)removeAllObjects;
- (void)addObject:(id)object;
- (void)addHit:(PopupEntry*)object;
- (id)objectAtIndex:(NSUInteger)index;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len;
- (NSUInteger)indexOfObject:(id)o;
- (void)sortByScore;
- (int)indexOfObjectWithMainValue:(NSString*)value;

@end
