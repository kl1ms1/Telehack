#import "THNetFilter.h"
#import "THFeatures.h"
#import "THSettings.h"
#import "THLog.h"

BOOL THNetHookInstalled = NO;

static NSData *THRequestPayload(id request) {
    // MTRequest exposes the serialized TL function as `payload`.
    @try {
        id payload = [request valueForKey:@"payload"];
        if ([payload isKindOfClass:[NSData class]]) return payload;
    } @catch (__unused NSException *e) {}
    return nil;
}

BOOL THNetFilterShouldDrop(id request) {
    NSData *payload = THRequestPayload(request);
    if (payload.length < 4) return NO;

    uint32_t constructor = 0;
    [payload getBytes:&constructor length:sizeof(constructor)];
    constructor = CFSwapInt32LittleToHost(constructor);

    THSettings *settings = [THSettings shared];
    BOOL drop = NO;

    THFeature *feature = [THFeatures featureForConstructor:constructor];
    if (feature && [settings isFeatureActive:feature]) drop = YES;
    if (!drop && [settings isCustomBlocked:constructor]) drop = YES;

    if (settings.loggingEnabled)
        [THLog recordConstructor:constructor length:payload.length blocked:drop];

    return drop;
}
