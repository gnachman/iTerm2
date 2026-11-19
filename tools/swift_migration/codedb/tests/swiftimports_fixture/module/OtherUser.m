// A unit of another target that defines PROBE_EXTRA, so that the database
// records the declarations Probe.h holds under #if PROBE_EXTRA.
#import "Probe.h"

void UseExtra(ProbeExtra *extra) {
    [extra extraOnly];
}
