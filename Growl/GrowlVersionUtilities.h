#ifndef _GROWLVERSIONUTILITIES_H
#define _GROWLVERSIONUTILITIES_H

#include "GrowlDefines.h"
#include <sys/types.h>
#include <stdbool.h>

enum releaseType {
	//release types
	releaseType_svn,
	releaseType_development,
	releaseType_alpha,
	releaseType_beta,
	releaseType_release,
	numberOfReleaseTypes //must be last
};
extern STRING releaseTypeNames[numberOfReleaseTypes];

#pragma options align=packed

struct Version {
	u_int16_t major;
	u_int16_t minor;
	u_int8_t  incremental;
	u_int8_t  releaseType; //use one of the constants for enum releaseType
	u_int32_t development; //for svn, should be the svn revision

	/*this structure can be taken as a 64-bit hexadecimal number:
	 *	0x0000 0006 00 01 svn_revision
	 *when releaseType is releaseType_release, the development version should
	 *	always be 0, and it should be ignored. (so, display "0.6", not "0.60".)
	 */
};

#pragma options align=reset

#define   STRUCT_VERSION_TO_64_BIT(v) (*(unsigned long long *)&(v))
#define STRUCT_VERSION_FROM_64_BIT(v) (*(struct Version *)&(v))

/*returns false if the version could not be parsed.
 *legend: 0.7.1svn1558
 *        A B CDDDEEEE
 *	A: major version
 *	B: minor version
 *	C: incremental version
 *	D: release type
 *	E: development version
 *spaces are allowed around the release type, and if the release type is svn,
 *	an optional 'r' is allowed immediately before the development version.
 */
bool parseVersionString(STRING string, struct Version *outVersion);

//this function follows CF rules for object retention: because it is a 'create' function, you must release the string you receive.
STRING createVersionDescription(const struct Version v);

/*these functions return:
 *	kCFCompareLessThan		a <  b
 *	kCFCompareEqualTo		a == b
 *	kCFCompareGreaterThan	a  > b
 */
CFComparisonResult compareVersions(const struct Version a, const struct Version b);
CFComparisonResult compareVersionStrings(STRING a, STRING b);
/*this version contains brain damage that translates "1.0" to "0.5" (handling
 *	the Growl 0.5 prefpane bundle, whose version was mistakenly set to "1.0").
 *the real Growl 1.0 prefpane bundle will have a version of "1.00".
 */
CFComparisonResult compareVersionStringsTranslating1_0To0_5(STRING a, STRING b);

#endif //ndef _GROWL_VERSIONUTILITIES_H
