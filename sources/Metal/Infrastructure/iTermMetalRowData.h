//
//  iTermMetalRowData.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 10/27/17.
//

#import <Foundation/Foundation.h>


@interface iTermMetalRowData : NSObject
@property (nonatomic) int y;
@property (nonatomic, strong) NSMutableData *keysData;
@property (nonatomic, strong) NSMutableData *attributesData;
@property (nonatomic, strong) NSMutableData *backgroundColorData;
@end

