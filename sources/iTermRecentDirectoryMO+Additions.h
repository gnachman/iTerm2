//
//  iTermRecentDirectoryMO+Additions.h
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import <Cocoa/Cocoa.h>
#import "iTermRecentDirectoryMO.h"

@interface iTermRecentDirectoryMO (Additions)

+ (NSString *)entityName;
+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary
                          inContext:(NSManagedObjectContext *)context;
- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                            abbreviationSafeComponents:(NSIndexSet *)abbreviationSafeIndexes;


// Take an attributedString having |path| with extra styles and remove bits from it to fit.
- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                               basedOnAttributedString:(NSAttributedString *)attributedString
                                        baseAttributes:(NSDictionary *)baseAttributes
                            abbreviationSafeComponents:(NSIndexSet *)abbreviationSafeIndexes;

@end

