/* =============================================================================
	FILE:		UKNibOwner.m
	PROJECT:	CocoaTADS

    COPYRIGHT:  (c) 2004 M. Uli Kusterer, all rights reserved.
    
	AUTHORS:	M. Uli Kusterer - UK
    
    LICENSES:   GPL, Modified BSD

	REVISIONS:
		2004-11-13	UK	Created.
   ========================================================================== */

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import "UKNibOwner.h"


@implementation UKNibOwner

// -----------------------------------------------------------------------------
//  init:
//      Create this object and load NIB file. Note that for subclasses, this
//      is called before your subclass has been fully constructed. I know this
//      sucks, because awakeFromNib can't rely on stuff that's done in the
//      constructor. I'll probably change this eventually.
//
//  REVISIONS:
//      2004-12-23  UK  Documented.
// -----------------------------------------------------------------------------

-(id)	init
{
	if( (self = [super init]) )
	{
		topLevelObjects = [[NSMutableArray alloc] init];
		NSDictionary*	ent = [NSDictionary dictionaryWithObjectsAndKeys:
									self, @"NSOwner",
									topLevelObjects, @"NSTopLevelObjects",
									nil];
		NSBundle*		mainB = [NSBundle mainBundle];
		[mainB loadNibFile: [self nibFilename]
							externalNameTable: ent withZone: [self zone]];	// We're responsible for releasing the top-level objects in the NIB (our view, right now).
		if( [topLevelObjects count] == 0 )
		{
			NSLog(@"%@: Couldn't find NIB file \"%@.nib\".", NSStringFromClass([self class]),[self nibFilename]);
			[self autorelease];
			return nil;
		}
	}
	
	return self;
}


-(void)	dealloc
{
	[topLevelObjects release];
	topLevelObjects = nil;
	
	[super dealloc];
}



// -----------------------------------------------------------------------------
//  nibFilename:
//      Return the filename (minus ".nib" suffix) for the NIB file to load.
//      Note that, if you subclass this, it will use the subclass's name, and
//      if you subclass that, the sub-subclass's name. So, you *may* want to
//      override this to return a constant string if you don't expect subclasses
//      to have their own similar-but-different NIB file.
//
//  REVISIONS:
//      2004-12-23  UK  Documented.
// -----------------------------------------------------------------------------

-(NSString*)    nibFilename
{
    return NSStringFromClass([self class]);
}

@end
