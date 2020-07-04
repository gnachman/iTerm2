//
//  CPTestErrorHandlingDelegate.h
//  CoreParse
//
//  Created by Thomas Davie on 05/02/2012.
//  Copyright (c) 2012 In The Beginning... All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreParse.h"

@interface CPTestErrorHandlingDelegate : NSObject <CPTokeniserDelegate, CPParserDelegate>

@property (readwrite, assign) BOOL hasEncounteredError;

@end
