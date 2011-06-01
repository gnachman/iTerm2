#!/usr/sbin/dtrace -s

RegexKitLite*:::compiledRegexCache {
  this->eventID         = (unsigned long)arg0;
  this->regexUTF8       = copyinstr(arg1);
  this->options         = (unsigned int)arg2;
  this->captures        = (int)arg3;
  this->hitMiss         = (int)arg4;
  this->icuStatusCode   = (int)arg5;
  this->icuErrorMessage = (arg6 == 0) ? "" : copyinstr(arg6);
  this->hitRate         = (double *)copyin(arg7, sizeof(double));

  printf("%5d: %-60.60s Opt: %#8.8x Cap: %2d Hit: %2d Rate: %6.2f%% code: %5d msg: %s\n",
         this->eventID,
         this->regexUTF8,
         this->options,
         this->captures,
         this->hitMiss,
         *this->hitRate,
         this->icuStatusCode,
         this->icuErrorMessage);
}
