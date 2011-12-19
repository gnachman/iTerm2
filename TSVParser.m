//
//  TSVParser.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TSVParser.h"


@implementation TSVDocument

@synthesize columns = columns_;
@synthesize records = records_;

- (id)init
{
    self = [super init];
    if (self) {
        records_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [columns_ release];
    [records_ release];
    [map_ release];
    [super dealloc];
}

- (NSString *)valueInRecord:(NSArray *)record forField:(NSString *)fieldName
{
    if (!map_) {
        map_ = [[NSMutableDictionary dictionary] retain];
        for (int i = 0; i < self.columns.count; i++) {
            [map_ setObject:[NSNumber numberWithInt:i]
                     forKey:[self.columns objectAtIndex:i]];
        }
    }
    
    NSNumber *n = [map_ objectForKey:fieldName];
    int i = [n intValue];
    if (n && i < [record count]) {
        return [record objectAtIndex:i];
    }
    return nil;
}

@end

@implementation TSVParser

+ (TSVDocument *)documentFromString:(NSString *)string
{
    NSArray *lines = [string componentsSeparatedByString:@"\n"];
    if ([lines count] == 0) {
        return nil;
    }
    TSVDocument *doc = [[[TSVDocument alloc] init] autorelease];
    NSString *header = [lines objectAtIndex:0];
    doc.columns = [[[header componentsSeparatedByString:@"\t"] mutableCopy] autorelease];
    for (int i = 1; i < lines.count; i++) {
        NSString *row = [lines objectAtIndex:i];
        [doc.records addObject:[row componentsSeparatedByString:@"\t"]];
    }
    return doc;
}

@end

@implementation NSString (TSV)

- (TSVDocument *)tsvDocument
{
    return [TSVParser documentFromString:self];
}

@end