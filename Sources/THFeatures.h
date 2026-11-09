#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// One "plugin": a named switch that blocks a set of outgoing MTProto functions
/// (identified by their TL constructor IDs).
@interface THFeature : NSObject
@property (nonatomic, copy, readonly) NSString *key;
@property (nonatomic, copy, readonly) NSString *section;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *subtitle;
@property (nonatomic, copy, readonly) NSArray<NSNumber *> *constructors;
/// If YES, the "read now" button temporarily lets these requests through.
@property (nonatomic, readonly) BOOL bypassedByReadUnlock;
@end

extern NSString *const THSectionGhost;
extern NSString *const THSectionPrivacy;
extern NSString *const THSectionAds;

@interface THFeatures : NSObject
+ (NSArray<THFeature *> *)all;
+ (NSArray<THFeature *> *)inSection:(NSString *)section;
+ (nullable THFeature *)featureForConstructor:(uint32_t)constructor;
/// Human readable TL name for the request log, nil if unknown.
+ (nullable NSString *)nameForConstructor:(uint32_t)constructor;
@end

NS_ASSUME_NONNULL_END
