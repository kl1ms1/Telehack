#import "THLog.h"
#import "THFeatures.h"

static const NSUInteger kMaxEntries = 300;

@implementation THLogEntry
- (NSString *)displayName {
    NSString *name = [THFeatures nameForConstructor:self.constructor];
    NSString *hex = [NSString stringWithFormat:@"0x%08x", self.constructor];
    return name ? [NSString stringWithFormat:@"%@ (%@)", name, hex] : hex;
}
@end

@implementation THLog

static NSMutableArray<THLogEntry *> *gEntries;

+ (void)initialize {
    if (self == [THLog class]) gEntries = [NSMutableArray array];
}

+ (void)recordConstructor:(uint32_t)constructor length:(NSUInteger)length blocked:(BOOL)blocked {
    THLogEntry *e = [THLogEntry new];
    e.date = [NSDate date];
    e.constructor = constructor;
    e.length = length;
    e.blocked = blocked;
    @synchronized (gEntries) {
        [gEntries addObject:e];
        if (gEntries.count > kMaxEntries)
            [gEntries removeObjectsInRange:NSMakeRange(0, gEntries.count - kMaxEntries)];
    }
}

+ (NSArray<THLogEntry *> *)entries {
    @synchronized (gEntries) {
        return gEntries.reverseObjectEnumerator.allObjects;
    }
}

+ (void)clear {
    @synchronized (gEntries) { [gEntries removeAllObjects]; }
}

+ (NSString *)exportText {
    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss.SSS";
    NSMutableString *s = [NSMutableString string];
    for (THLogEntry *e in [self entries])
        [s appendFormat:@"%@ %@ %@ %luB\n", [f stringFromDate:e.date], e.blocked ? @"BLOCK" : @"pass ",
                        e.displayName, (unsigned long)e.length];
    return s;
}

@end
