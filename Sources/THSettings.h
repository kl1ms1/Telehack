#import <Foundation/Foundation.h>
@class THFeature;

NS_ASSUME_NONNULL_BEGIN

extern NSString *const THSettingsChangedNotification;

@interface THSettings : NSObject
+ (instancetype)shared;

- (BOOL)boolForKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;

/// Is this plugin enabled right now (switch on and not temporarily bypassed)?
- (BOOL)isFeatureActive:(THFeature *)feature;

/// "Read now": lets read-type requests through until this moment.
- (void)unlockReadsFor:(NSTimeInterval)seconds;
@property (nonatomic, readonly) NSTimeInterval readUnlockRemaining;

/// User-defined constructor IDs to block (custom rules).
@property (nonatomic, copy) NSArray<NSNumber *> *customBlocked;
- (BOOL)isCustomBlocked:(uint32_t)constructor;

@property (nonatomic, getter=isLoggingEnabled) BOOL loggingEnabled;
@end

NS_ASSUME_NONNULL_END
