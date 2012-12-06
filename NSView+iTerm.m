//
//  NSView+iTerm.m
//  iTerm
//
//  Created by George Nachman on 12/5/12.
//
//

#import "NSView+iTerm.h"

@implementation NSView (iTerm)

// http://stackoverflow.com/questions/4166879/how-to-print-a-control-hierarchy-in-cocoa
+ (NSString *)hierarchicalDescriptionOfView:(NSView *)view
                                      level:(NSUInteger)level
{
    // Ready the description string for this level
    NSMutableString * builtHierarchicalString = [NSMutableString string];

    // Build the tab string for the current level's indentation
    NSMutableString * tabString = [NSMutableString string];
    for (NSUInteger i = 0; i <= level; i++)
        [tabString appendString:@"\t"];

    // Get the view's title string if it has one
    NSString * titleString = ([view respondsToSelector:@selector(title)]) ?
        [NSString stringWithFormat:@"%@", [NSString stringWithFormat:@"\"%@\" ", [(NSButton *)view title]]] :
        @"";

    // Append our own description at this level
    [builtHierarchicalString appendFormat:@"\n%@%@ %@ %@(%li subviews)", tabString, view, [NSValue valueWithRect:view.frame], titleString, [[view subviews] count]];

    // Recurse for each subview ...
    for (NSView * subview in [view subviews])
        [builtHierarchicalString appendString:[NSView hierarchicalDescriptionOfView:subview
                                                                              level:(level + 1)]];

    return builtHierarchicalString;
}

- (NSString *)hierarchicalDescription
{
    return [[self class] hierarchicalDescriptionOfView:self level:0];
}

@end
