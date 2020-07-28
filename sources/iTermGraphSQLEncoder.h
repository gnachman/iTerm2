//
//  iTermGraphSQLEncoder.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/28/20.
//

#import <Foundation/Foundation.h>

#import "iTermEncoderGraphRecord.h"
#import "iTermGraphDeltaEncoder.h"

NS_ASSUME_NONNULL_BEGIN

// Encodes a graph to a series of update, insert, and delete instructions.
// Usage:
//
// iTermEncoderGraphRecord *saved =
//   [[[iTermGraphTableTransformer alloc] initWithNodeRows:nodes
//                                               valueRows:values] root];
// iTermGraphDeltaEncoder *encoder = [[iTermGraphSQLEncoder alloc] initWithRecord:saved];
// NSArray<NSString *> *sql =
//   [encoder sqlStatementsForNextRevision:^(iTermGraphEncoder *encoder) {
//     [encoder encodeString:@"red" forKey:@"color"];
//     [encoder encodeChildWithKey:@"tab"
//                      identifier:@"123-456"
//                      generation:tab.generation
//                           block:^(iTermGraphEncoder *subencoder) {
//       [subencoder encodeString:@"Hello world" forKey:@"title"];
//       for (LineBlock *block in blocks) {
//         [subencoder encodeChildWithKey:@"LineBlock"
//                             identifier:block.guid
//                             generation:block.generation
//                                  block:^(iTermGraphEncoder *blockEncoder) {
//           [blockEncoder encodeData:block.data forKey:@"data"];
//         }];
//       }
//     }];
@interface iTermGraphSQLEncoder: NSObject
@property (nonatomic, readonly) iTermEncoderGraphRecord *root;

- (instancetype)initWithRecord:(iTermEncoderGraphRecord *)record NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSArray<NSString *> *)sqlStatementsForNextRevision:(void (^ NS_NOESCAPE)(iTermGraphDeltaEncoder *encoder))block;

@end

NS_ASSUME_NONNULL_END
