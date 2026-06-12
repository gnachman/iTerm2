//
//  iTermTerminfoHelper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 7/18/24.
//

struct termtype;

// This file exists to work around absurd problems in ncurses, such as defining `struct entry`.

// Get the number of keys of each type.
int iTermTerminfoNumberOfStrings(struct termtype *termType);
int iTermTerminfoNumberOfBooleans(struct termtype *termType);
int iTermTerminfoNumberOfNumbers(struct termtype *termType);

// Get the `i`th key for the type.
// These can be passed to tiget{str,flag,num}.
char *iTermTerminfoStringName(struct termtype *termType, int i);
char *iTermTerminfoBooleanName(struct termtype *termType, int i);
char *iTermTerminfoNumberName(struct termtype *termType, int i);

