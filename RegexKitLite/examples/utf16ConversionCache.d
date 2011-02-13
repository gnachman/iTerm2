#!/usr/sbin/dtrace -s

enum {
  RKLCacheHitLookupFlag           = 1 << 0,
  RKLConversionRequiredLookupFlag = 1 << 1,
  RKLSetTextLookupFlag            = 1 << 2,
  RKLDynamicBufferLookupFlag      = 1 << 3,
  RKLErrorLookupFlag              = 1 << 4
};

RegexKitLite*:::utf16ConversionCache {
  this->eventID           = (unsigned long)arg0;
  this->lookupResultFlags = (unsigned int)arg1;
  this->hitRate           = (double *)copyin(arg2, sizeof(double));
  this->stringPtr         = (void *)arg3;
  this->NSRange_location  = (unsigned long)arg4;
  this->NSRange_length    = (unsigned long)arg5;
  this->length            = (long)arg6;

  printf("%5lu: flags: %#8.8x {Hit: %d Conv: %d SetText: %d Dyn: %d Error: %d} rate: %6.2f%% string: %#8.8p NSRange {%6lu, %6lu} length: %ld\n", 
	 this->eventID,
	 this->lookupResultFlags,
	 (this->lookupResultFlags & RKLCacheHitLookupFlag)           != 0,
	 (this->lookupResultFlags & RKLConversionRequiredLookupFlag) != 0,
	 (this->lookupResultFlags & RKLSetTextLookupFlag)            != 0,
	 (this->lookupResultFlags & RKLDynamicBufferLookupFlag)      != 0,
	 (this->lookupResultFlags & RKLErrorLookupFlag)              != 0,
	 *this->hitRate,
	 this->stringPtr,
	 this->NSRange_location,
	 this->NSRange_length,
	 this->length);
}
