//
//  iTermRecentDirectoryMO+Additions.m
//  iTerm2
//
//  Created by George Nachman on 10/11/15.
//
//

#import "iTermRecentDirectoryMO+Additions.h"
#import "iTermDirectoryTree.h"
#import "NSArray+iTerm.h"
#import "NSMutableAttributedString+iTerm.h"

static NSString *const kDirectoryEntryPath = @"path";
static NSString *const kDirectoryEntryUseCount = @"use count";
static NSString *const kDirectoryEntryLastUse = @"last use";
static NSString *const kDirectoryEntryIsStarred = @"starred";

@implementation iTermRecentDirectoryMO (Additions)

+ (NSString *)entityName {
    return @"RecentDirectory";
}

+ (instancetype)entryWithDictionary:(NSDictionary *)dictionary
                          inContext:(NSManagedObjectContext *)context {
    iTermRecentDirectoryMO *entry = [NSEntityDescription insertNewObjectForEntityForName:[self entityName]
                                                                  inManagedObjectContext:context];

    entry.path = dictionary[kDirectoryEntryPath];
    entry.useCount = dictionary[kDirectoryEntryUseCount];
    entry.lastUse = dictionary[kDirectoryEntryLastUse];
    entry.starred = dictionary[kDirectoryEntryIsStarred];
    return entry;
}

- (NSComparisonResult)compare:(iTermRecentDirectoryMO *)other {
    if (self.starred.boolValue && !other.starred.boolValue) {
        return NSOrderedAscending;
    } else if (!self.starred.boolValue && other.starred.boolValue) {
        return NSOrderedDescending;
    }

    if ((int)log2(self.useCount.integerValue) > (int)log2(other.useCount.integerValue)) {
        return NSOrderedAscending;
    } else if ((int)log2(self.useCount.integerValue) < (int)log2(other.useCount.integerValue)) {
        return NSOrderedDescending;
    }

    NSComparisonResult result = [other.lastUse compare:self.lastUse];
    if (result != NSOrderedSame) {
        return result;
    }

    // Fall back on small differences of use count. Ordinarily lastUse will always differ so we
    // won't get here, but this makes unit tests easier to write since the order will be predictable.
    return [other.useCount compare:self.useCount];
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                               basedOnAttributedString:(NSAttributedString *)attributedString
                                        baseAttributes:(NSDictionary *)baseAttributes
                            abbreviationSafeComponents:(NSIndexSet *)abbreviationSafeIndexes {
    NSFont *font = [[aTableColumn dataCell] font];
    // Split up the passed-in attributed string into components.
    // There is a wee bug where attributes on slashes are lost.
    NSMutableArray *components = [iTermDirectoryTree attributedComponentsInPath:attributedString];

    // Initialize attributes.
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    style.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:baseAttributes];
    attributes[NSFontAttributeName] = font;
    attributes[NSParagraphStyleAttributeName] = style;

    // Compute the prefix of the result.
    NSMutableAttributedString *result = [[[NSMutableAttributedString alloc] init] autorelease];
    NSString *prefix = self.starred.boolValue ? @"★ /" : @"/";
    [result iterm_appendString:prefix withAttributes:attributes];
    NSAttributedString *attributedSlash =
        [[[NSAttributedString alloc] initWithString:@"/" attributes:attributes] autorelease];

    // Initialize the abbreviated name in case no further changes are made.
    NSMutableAttributedString *abbreviatedName = [[[NSMutableAttributedString alloc] init] autorelease];
    [abbreviatedName iterm_appendString:prefix withAttributes:attributes];
    NSAttributedString *attributedPath =
        [components attributedComponentsJoinedByAttributedString:attributedSlash];
    [abbreviatedName appendAttributedString:attributedPath];

    // Abbreviate each allowed component until it fits. The last component can't be abbreviated.
    CGFloat maxWidth = aTableColumn.width;
    for (int i = 0; i + 1 < components.count && [abbreviatedName size].width > maxWidth; i++) {
        if ([abbreviationSafeIndexes containsIndex:i]) {
            components[i] = [components[i] attributedSubstringFromRange:NSMakeRange(0, 1)];
        }
        [abbreviatedName deleteCharactersInRange:NSMakeRange(0, abbreviatedName.length)];
        [abbreviatedName iterm_appendString:prefix withAttributes:attributes];
        attributedPath = [components attributedComponentsJoinedByAttributedString:attributedSlash];
        [abbreviatedName appendAttributedString:attributedPath];
    }

    return abbreviatedName;
}

- (NSAttributedString *)attributedStringForTableColumn:(NSTableColumn *)aTableColumn
                            abbreviationSafeComponents:(NSIndexSet *)abbreviationSafeIndexes {
    NSAttributedString *theString =
        [[[NSAttributedString alloc] initWithString:self.path ?: @""] autorelease];
    return [self attributedStringForTableColumn:aTableColumn
                        basedOnAttributedString:theString
                                 baseAttributes:@{}
                     abbreviationSafeComponents:abbreviationSafeIndexes];
}

@end
