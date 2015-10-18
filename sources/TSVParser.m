//
//  TSVParser.m
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import "TSVParser.h"


@implementation TSVDocument {
    NSMutableDictionary *map_;
}

@synthesize columns = columns_;
@synthesize records = records_;

- (instancetype)init {
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

+ (TSVDocument *)documentFromString:(NSString *)string withFields:(NSArray *)fields
{
    NSArray *lines = [string componentsSeparatedByString:@"\n"];
    if ([lines count] == 0) {
        return nil;
    }
    TSVDocument *doc = [[[TSVDocument alloc] init] autorelease];
    doc.columns = [[fields copy] autorelease];
    for (int i = 0; i < lines.count; i++) {
        NSString *row = [lines objectAtIndex:i];
        NSArray *rowArray = [row componentsSeparatedByString:@"\t"];
        if (rowArray.count >= fields.count) {
            [doc.records addObject:rowArray];
        }
    }
    return doc;
}

@end

@implementation NSString (TSV)

- (TSVDocument *)tsvDocumentWithFields:(NSArray *)fields
{
    return [TSVParser documentFromString:self withFields:fields];
}

@end
