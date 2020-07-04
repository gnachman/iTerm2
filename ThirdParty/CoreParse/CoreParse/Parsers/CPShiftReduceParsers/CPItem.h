//
//  CPItem.h
//  CoreParse
//
//  Created by Tom Davie on 06/03/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CPRule.h"
#import "CPGrammarSymbol.h"

@interface CPItem : NSObject <NSCopying>
{}

@property (readonly,retain) CPRule *rule;
@property (readonly,assign) NSUInteger position;

+ (id)itemWithRule:(CPRule *)rule position:(NSUInteger)position;
- (id)initWithRule:(CPRule *)rule position:(NSUInteger)position;

- (CPGrammarSymbol *)nextSymbol;
- (NSArray *)followingSymbols;

- (id)itemByMovingDotRight;

- (BOOL)isEqualToItem:(CPItem *)item;

@end

@interface NSObject (CPIsItem)

- (BOOL)isItem;

@end
