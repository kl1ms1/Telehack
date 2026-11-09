#import <Foundation/Foundation.h>

/// Runs a couple of connectivity probes and calls back (on the main queue)
/// with a human-readable multi-line result, so we can tell whether the resigned
/// copy has working network at all, or only Telegram's MTProto path is broken.
void THDiagRun(void (^completion)(NSString *report));
