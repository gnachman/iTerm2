/* =============================================================================
	FILE:		UKNibOwner.h
	PROJECT:	CocoaTADS

    COPYRIGHT:  (c) 2004 M. Uli Kusterer, all rights reserved.
    
	AUTHORS:	M. Uli Kusterer - UK
    
    LICENSES:   GPL, Modified BSD

	REVISIONS:
		2004-11-13	UK	Created.
   ========================================================================== */

/*
	UKNibOwner is a little base class for your classes. It automatically loads
	a NIB file with the same name as your class (e.g. "UKNibOwnerSubClass.nib")
	and takes care of releasing all top-level objects in the NIB when it is
	released. All you have to do is hook up the outlets in the NIB.
*/

// -----------------------------------------------------------------------------
//  Headers:
// -----------------------------------------------------------------------------

#import <Cocoa/Cocoa.h>


// -----------------------------------------------------------------------------
//  Classes:
// -----------------------------------------------------------------------------

@interface UKNibOwner : NSObject
{
    NSMutableArray*     topLevelObjects;
}

-(NSString*)    nibFilename;    // Defaults to name of the class.

@end
