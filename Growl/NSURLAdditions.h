//
//  NSURLAdditions.h
//  Growl
//
//  Created by Karl Adam on Fri May 28 2004.
//  Copyright 2004-2005 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details

#import <Foundation/Foundation.h>

@interface NSURL (GrowlAdditions)

//'alias' as in the Alias Manager.
+ (NSURL *) fileURLWithAliasData:(NSData *)aliasData;
- (NSData *) aliasData;

//these are the type of external representations used by Dock.app.
+ (NSURL *) fileURLWithDockDescription:(NSDictionary *)dict;
//-dockDescription returns nil for non-file: URLs.
- (NSDictionary *) dockDescription;

@end
