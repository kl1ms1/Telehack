#import "THSettings.h"
#import "THFeatures.h"

NSString *const THSettingsChangedNotification = @"THSettingsChangedNotification";
static NSString *const kPrefix = @"telehack.";

@implementation THSettings {
    NSUserDefaults *_defaults;
    NSSet<NSNumber *> *_customSet;   // read on the network queue
    NSDate *_readUnlockUntil;
    NSLock *_lock;
}

+ (instancetype)shared {
    static THSettings *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _defaults = [NSUserDefaults standardUserDefaults];
        _lock = [NSLock new];
        _customSet = [NSSet setWithArray:self.customBlocked];
    }
    return self;
}

- (BOOL)boolForKey:(NSString *)key {
    return [_defaults boolForKey:[kPrefix stringByAppendingString:key]];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key {
    [_defaults setBool:value forKey:[kPrefix stringByAppendingString:key]];
    [[NSNotificationCenter defaultCenter] postNotificationName:THSettingsChangedNotification object:self];
}

- (BOOL)isFeatureActive:(THFeature *)feature {
    if (![self boolForKey:feature.key]) return NO;
    if (feature.bypassedByReadUnlock && self.readUnlockRemaining > 0) return NO;
    return YES;
}

- (void)unlockReadsFor:(NSTimeInterval)seconds {
    [_lock lock];
    _readUnlockUntil = [NSDate dateWithTimeIntervalSinceNow:seconds];
    [_lock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:THSettingsChangedNotification object:self];
}

- (NSTimeInterval)readUnlockRemaining {
    [_lock lock];
    NSTimeInterval t = _readUnlockUntil ? _readUnlockUntil.timeIntervalSinceNow : 0;
    [_lock unlock];
    return MAX(t, 0);
}

- (NSArray<NSNumber *> *)customBlocked {
    NSArray *a = [_defaults arrayForKey:[kPrefix stringByAppendingString:@"custom"]];
    return [a isKindOfClass:[NSArray class]] ? a : @[];
}

- (void)setCustomBlocked:(NSArray<NSNumber *> *)customBlocked {
    [_defaults setObject:customBlocked ?: @[] forKey:[kPrefix stringByAppendingString:@"custom"]];
    NSSet *set = [NSSet setWithArray:customBlocked ?: @[]];
    [_lock lock];
    _customSet = set;
    [_lock unlock];
    [[NSNotificationCenter defaultCenter] postNotificationName:THSettingsChangedNotification object:self];
}

- (BOOL)isCustomBlocked:(uint32_t)constructor {
    [_lock lock];
    BOOL r = [_customSet containsObject:@(constructor)];
    [_lock unlock];
    return r;
}

- (BOOL)isLoggingEnabled { return [self boolForKey:@"debug.log"]; }
- (void)setLoggingEnabled:(BOOL)on { [self setBool:on forKey:@"debug.log"]; }

@end
