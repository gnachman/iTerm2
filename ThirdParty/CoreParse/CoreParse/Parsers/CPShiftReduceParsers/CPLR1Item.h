//
//  CPLR1Item.h
//  CoreParse
//
//  Created by Tom Davie on 12/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPItem.h"
#import "CPGrammarSymbol.h"

@interface CPLR1Item : CPItem
{}

@property (readonly,retain) CPGrammarSymbol *terminal;

+ (id)lr1ItemWithRule:(CPRule *)rule position:(NSUInteger)position terminal:(CPGrammarSymbol *)terminal;
- (id)initWithRule:(CPRule *)rule position:(NSUInteger)position terminal:(CPGrammarSymbol *)terminal;

@end

@interface NSObject (CPIsLR1Item)

- (BOOL)isLR1Item;

@end
