//
//  TSVParser.h
//  iTerm
//
//  Created by George Nachman on 11/27/11.
//

#import <Cocoa/Cocoa.h>


@interface TSVDocument : NSObject

@property (nonatomic, retain) NSMutableArray *columns;
@property (nonatomic, readonly) NSMutableArray *records;

- (NSString *)valueInRecord:(NSArray *)record forField:(NSString *)fieldName;

@end

@interface TSVParser : NSObject

+ (TSVDocument *)documentFromString:(NSString *)string
                         withFields:(NSArray *)fields
                   workAroundTabBug:(BOOL)workAroundTabBug;

@end

@interface NSString (TSV)

- (TSVDocument *)tsvDocumentWithFields:(NSArray *)fields workAroundTabBug:(BOOL)workAroundTabBug;

@end
