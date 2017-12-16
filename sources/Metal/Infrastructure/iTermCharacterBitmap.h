//
//  iTermCharacterBitmap.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/15/17.
//

#import <Foundation/Foundation.h>

// Contains raw pixels for a single part of a character.
@interface iTermCharacterBitmap : NSObject
@property (nonatomic, strong) NSMutableData *data;
@property (nonatomic) CGSize size;
@end

