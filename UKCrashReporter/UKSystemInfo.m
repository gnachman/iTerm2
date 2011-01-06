//
//  UKSystemInfo.m
//  UKSystemInfo
//
//  Created by Uli Kusterer on 23.09.04.
//  Copyright 2004 M. Uli Kusterer. All rights reserved.
//

#import "UKSystemInfo.h"
#include <Carbon/Carbon.h>
#include <sys/types.h>
#include <sys/sysctl.h>

unsigned	UKPhysicalRAMSize()
{
	long		ramSize;
	
	if( Gestalt( gestaltPhysicalRAMSizeInMegabytes, &ramSize ) == noErr )
		return ramSize;
	else
		return 0;
}


NSString*	UKSystemVersionString()
{
	long		vMajor = 10, vMinor = 0, vBugfix = 0;
	UKGetSystemVersionComponents( &vMajor, &vMinor, &vBugfix );
	
	return [NSString stringWithFormat: @"%ld.%ld.%ld", vMajor, vMinor, vBugfix];
}


void	UKGetSystemVersionComponents( long* outMajor, long* outMinor, long* outBugfix )
{
	long		sysVersion = UKSystemVersion();
	if( sysVersion >= MAC_OS_X_VERSION_10_4 )
	{
		Gestalt( gestaltSystemVersionMajor, outMajor );
		Gestalt( gestaltSystemVersionMinor, outMinor );
		Gestalt( gestaltSystemVersionBugFix, outBugfix );
	}
	else
	{
		*outMajor = ((sysVersion & 0x0000F000) >> 12) * 10 + ((sysVersion & 0x00000F00) >> 8);
		*outMinor = (sysVersion & 0x000000F0) >> 4;
		*outBugfix = sysVersion & 0x0000000F;
	}
}


long	UKSystemVersion()
{
	long		sysVersion;
	
	if( Gestalt( gestaltSystemVersion, &sysVersion ) != noErr )
		return 0;
	
	return sysVersion;
}


unsigned	UKClockSpeed()
{
	long		speed;
	
	if( Gestalt( gestaltProcClkSpeed, &speed ) == noErr )
		return speed / 1000000;
	else
		return 0;
}


unsigned	UKCountCores()
{
	unsigned	count = 0;
	size_t		size = sizeof(count);

	if( sysctlbyname( "hw.ncpu", &count, &size, NULL, 0 ) )
		return 1;

	return count;
}


NSString*	UKMachineName()
{
	static NSString*	cpuName = nil;
	if( cpuName )
		return cpuName;
	
	char*				machineName = NULL;
	
	if( Gestalt( gestaltUserVisibleMachineName, (long*) &machineName ) == noErr )
	{
		NSString*	internalName = [NSString stringWithCString: machineName +1 length: machineName[0]];
		
		NSDictionary* translationDictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
					@"PowerMac 8500/8600",@"AAPL,8500",
					@"PowerMac 9500/9600",@"AAPL,9500",
					@"PowerMac 7200",@"AAPL,7200",
					@"PowerMac 7200/7300",@"AAPL,7300",
					@"PowerMac 7500",@"AAPL,7500",
					@"Apple Network Server",@"AAPL,ShinerESB",
					@"Alchemy(Performa 6400 logic-board design)",@"AAPL,e407",
					@"Gazelle(5500)",@"AAPL,e411",
					@"PowerBook 3400",@"AAPL,3400/2400",
					@"PowerBook 3500",@"AAPL,3500",
					@"PowerMac G3 (Gossamer)",@"AAPL,Gossamer",
					@"PowerMac G3 (Silk)",@"AAPL,PowerMac G3",
					@"PowerBook G3 (Wallstreet)",@"AAPL,PowerBook1998",
					@"Yikes! Old machine",@"AAPL",		// generic.
					
					@"iMac (first generation)",@"iMac,1",
					@"iMac",@"iMac",					// generic.
					
					@"PowerBook G3 (Lombard)",@"PowerBook1,1",
					@"iBook (clamshell)",@"PowerBook2,1",
					@"iBook FireWire (clamshell)",@"PowerBook2,2",
					@"PowerBook G3 (Pismo)",@"PowerBook3,1",
					@"PowerBook G4 (Titanium)",@"PowerBook3,2",
					@"PowerBook G4 (Titanium w/ Gigabit Ethernet)",@"PowerBook3,3",
					@"PowerBook G4 (Titanium w/ DVI)",@"PowerBook3,4",
					@"PowerBook G4 (Titanium 1GHZ)",@"PowerBook3,5",
					@"iBook (12in May 2001)",@"PowerBook4,1",
					@"iBook (May 2002)",@"PowerBook4,2",
					@"iBook 2 rev. 2 (w/ or w/o 14in LCD) (Nov 2002)",@"PowerBook4,3",
					@"iBook 2 (w/ or w/o 14in LDC)",@"PowerBook4,4",
					@"PowerBook G4 (Aluminum 17in)",@"PowerBook5,1",
					@"PowerBook G4 (Aluminum 15in)",@"PowerBook5,2",
					@"PowerBook G4 (Aluminum 17in rev. 2)",@"PowerBook5,3",
					@"PowerBook G4 (Aluminum 12in)",@"PowerBook6,1",
					@"PowerBook G4 (Aluminum 12in)",@"PowerBook6,2",
					@"iBook G4",@"PowerBook6,3",
					@"PowerBook or iBook",@"PowerBook",	// generic.
					
					@"Blue & White G3",@"PowerMac1,1",
					@"PowerMac G4 PCI Graphics",@"PowerMac1,2",
					@"iMac FireWire (CRT)",@"PowerMac2,1",
					@"iMac FireWire (CRT)",@"PowerMac2,2",
					@"PowerMac G4 AGP Graphics",@"PowerMac3,1",
					@"PowerMac G4 AGP Graphics",@"PowerMac3,2",
					@"PowerMac G4 AGP Graphics",@"PowerMac3,3",
					@"PowerMac G4 (QuickSilver)",@"PowerMac3,4",
					@"PowerMac G4 (QuickSilver)",@"PowerMac3,5",
					@"PowerMac G4 (MDD/Windtunnel)",@"PowerMac3,6",
					@"iMac (Flower Power)",@"PowerMac4,1",
					@"iMac (Flat Panel 15in)",@"PowerMac4,2",
					@"eMac",@"PowerMac4,4",
					@"iMac (Flat Panel 17in)",@"PowerMac4,5",
					@"PowerMac G4 Cube",@"PowerMac5,1",
					@"PowerMac G4 Cube",@"PowerMac5,2",
					@"iMac (Flat Panel 17in)",@"PowerMac6,1",
					@"PowerMac G5",@"PowerMac7,2",
					@"PowerMac G5",@"PowerMac7,3",
					@"PowerMac",@"PowerMac",	// generic.
					
					@"XServe",@"RackMac1,1",
					@"XServe rev. 2",@"RackMac1,2",
					@"XServe G5",@"RackMac3,1",
					@"XServe",@"RackMac",
					
					@"Mac Mini",@"Macmini1,1",	// Core Duo?
					@"Mac Mini",@"Macmini",		// generic
					
					nil];
		
		NSRange			r;
		NSString*		aKey;
		NSString*		foundKey = nil;
		NSString*		humanReadableName = nil;
		
		// Find the corresponding entry in the NSDictionary
		//	Keys should be sorted to distinguish 'generic' from 'specific' names.
		//	So we can overwrite generic names with the more specific ones as we
		//	progress through the list.
		NSEnumerator	*e=[[[translationDictionary allKeys]
									sortedArrayUsingSelector:@selector(compare:)]
									objectEnumerator];
		while( aKey = [e nextObject] )
		{
			r = [internalName rangeOfString: aKey];
			if( r.location != NSNotFound )
			{
				if( humanReadableName == nil || [foundKey length] != [internalName length] )	// We didn't have an exact match yet?
				{
					humanReadableName = [translationDictionary objectForKey:aKey];
					foundKey = aKey;
				}
			}
		}
		
		// If it was a generic name, include the ugly name so we can add it to the list:
		if( [foundKey rangeOfString: @","].location == NSNotFound )
			humanReadableName = [[NSString stringWithFormat: @"%@ (%@)", humanReadableName, foundKey] retain];
		// If nothing was found, at least show the ugly name so we have some hint:
		if( humanReadableName == nil )
			cpuName = [[NSString stringWithFormat: @"Unknown (%@)", internalName] retain];
		else
			cpuName = humanReadableName;
	}
	
	return cpuName;
}


NSString*	UKCPUName()
{
	return UKAutoreleasedCPUName( NO );
}


NSString*	UKAutoreleasedCPUName( BOOL releaseIt )
{
	long				cpu;
	static NSString*	cpuName = nil;
	
	if( Gestalt( gestaltNativeCPUtype, &cpu ) == noErr )
	{
		if( !cpuName )
		{
			NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
										@"Motorola 68000", [NSNumber numberWithLong: gestaltCPU68000],
										@"Motorola 68010", [NSNumber numberWithLong: gestaltCPU68010],
										@"Motorola 68020", [NSNumber numberWithLong: gestaltCPU68020],
										@"Motorola 68030", [NSNumber numberWithLong: gestaltCPU68030],
										@"Motorola 68040", [NSNumber numberWithLong: gestaltCPU68040],
										@"PowerPC 601", [NSNumber numberWithLong: gestaltCPU601],
										@"PowerPC 603", [NSNumber numberWithLong: gestaltCPU603],
										@"PowerPC 604", [NSNumber numberWithLong: gestaltCPU604],
										@"PowerPC 603e", [NSNumber numberWithLong: gestaltCPU603e],
										@"PowerPC 603ev", [NSNumber numberWithLong: gestaltCPU603ev],
										@"PowerPC G3", [NSNumber numberWithLong: gestaltCPU750],
										@"PowerPC 604e", [NSNumber numberWithLong: gestaltCPU604e],
										@"PowerPC 604ev", [NSNumber numberWithLong: gestaltCPU604ev],
										@"PowerPC G4", [NSNumber numberWithLong: gestaltCPUG4],
										@"PowerPC G4", [NSNumber numberWithLong: gestaltCPUG47450],
										nil
									];
			cpuName = [dict objectForKey: [NSNumber numberWithLong: cpu]];
		}
		if( cpuName == nil )
		{
			char	cpuCStr[5] = { 0 };
			memmove( cpuCStr, &cpu, 4 );
			if( (cpu & 0xff000000) >= 0x20000000 && (cpu & 0x00ff0000) >= 0x00200000
				&& (cpu & 0x0000ff00) >= 0x00002000 && (cpu & 0x000000ff) >= 0x00000020)	// All valid as characters?
				cpuName = [NSString stringWithFormat: @"Unknown (%d/%s)", cpu, &cpu];
			else
				cpuName = [NSString stringWithFormat: @"Unknown (%d)", cpu, &cpu];
		}
		[cpuName retain];		// Yeah, I know, I'm paranoid.
	}

	if( releaseIt )
	{
		NSString*	cn = cpuName;
		[cpuName autorelease];
		cpuName = nil;
		return cn;
	}
	
	return cpuName;
}


/*NSString*	UKSystemSerialNumber()
{
	mach_port_t				masterPort;
	kern_return_t			kr = noErr;
	io_registry_entry_t		entry;
	CFTypeRef				prop;
	CFTypeID				propID;
	NSString*				str = nil;

	kr = IOMasterPort(MACH_PORT_NULL, &masterPort);
	if( kr != noErr )
		goto cleanup;
	entry = IORegistryGetRootEntry( masterPort );
	if( entry == MACH_PORT_NULL )
		goto cleanup;
	prop = IORegistryEntrySearchCFProperty(entry, kIODeviceTreePlane, CFSTR("serial-number"), nil, kIORegistryIterateRecursively);
	if( prop == nil )
		goto cleanup;
	propID = CFGetTypeID( prop );
	if( propID != CFDataGetTypeID() )
		goto cleanup;
	
	const char*	buf = [(NSData*)prop bytes];
	int			len = [(NSData*)prop length],
				 x;
	
	char	secondPart[256];
	char	firstPart[256];
	char*	currStr = secondPart;
	int		y = 0;
	
	for( x = 0; x < len; x++ )
	{
		if( buf[x] > 0 && (y < 255) )
			currStr[y++] = buf[x];
		else if( currStr == secondPart )
		{
			currStr[y] = 0;		// Terminate string.
			currStr = firstPart;
			y = 0;
		}
	}
	currStr[y] = 0;	// Terminate string.
	
	str = [NSString stringWithFormat: @"%s%s", firstPart, secondPart];
	
cleanup:
	mach_port_deallocate( mach_task_self(), masterPort );
	
	return str;
}*/

