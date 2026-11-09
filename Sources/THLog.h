#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface THLogEntry : NSObject
@property (nonatomic, strong) NSDate *date;
@property (nonatomic) uint32_t constructor;
@property (nonatomic) NSUInteger length;
@property (nonatomic) BOOL blocked;
@property (nonatomic, readonly) NSString *displayName;
@end

/// Ring buffer of recent outgoing requests. Lets users discover constructor
/// IDs when Telegram changes its API layer.
@interface THLog : NSObject
+ (void)recordConstructor:(uint32_t)constructor length:(NSUInteger)length blocked:(BOOL)blocked;
+ (NSArray<THLogEntry *> *)entries; // newest first
+ (void)clear;
+ (NSString *)exportText;
@end

NS_ASSUME_NONNULL_END
