//
//  Expression.h
//  CoreParse
//
//  Created by Thomas Davie on 26/06/2011.
//  Copyright 2011 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import <CoreParse/CoreParse.h>

@interface Expression : NSObject <CPParseResult>

@property (readwrite,assign) float value;

@end
