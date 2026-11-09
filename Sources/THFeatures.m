#import "THFeatures.h"

NSString *const THSectionGhost = @"ghost";
NSString *const THSectionPrivacy = @"privacy";
NSString *const THSectionAds = @"ads";

@interface THFeature ()
@property (nonatomic, copy, readwrite) NSString *key;
@property (nonatomic, copy, readwrite) NSString *section;
@property (nonatomic, copy, readwrite) NSString *title;
@property (nonatomic, copy, readwrite) NSString *subtitle;
@property (nonatomic, copy, readwrite) NSArray<NSNumber *> *constructors;
@property (nonatomic, readwrite) BOOL bypassedByReadUnlock;
@end

@implementation THFeature
@end

static THFeature *F(NSString *key, NSString *section, NSString *title, NSString *subtitle,
                    BOOL bypass, NSArray<NSNumber *> *cids) {
    THFeature *f = [THFeature new];
    f.key = key;
    f.section = section;
    f.title = title;
    f.subtitle = subtitle;
    f.bypassedByReadUnlock = bypass;
    f.constructors = cids;
    return f;
}

// TL constructor IDs of MTProto functions (see core.telegram.org/schema).
// If Telegram bumps a constructor in a new layer, find the new ID in the
// in-app request log and add it here (or as a custom rule in the panel).
#define TL_account_updateStatus              0x6628562c
#define TL_messages_readHistory              0x0e306d3a
#define TL_channels_readHistory              0xcc104937
#define TL_messages_readEncryptedHistory     0x7f4b690a
#define TL_messages_readDiscussion           0xf731a9f4
#define TL_messages_readMentions             0x36e5bf4d
#define TL_messages_readReactions            0x54aa7f8e
#define TL_messages_readMessageContents      0x36a73f77
#define TL_channels_readMessageContents      0xeab5dc38
#define TL_messages_setTyping                0x58943ee2
#define TL_messages_setEncryptedTyping       0x791451ed
#define TL_stories_readStories               0xa556dac8
#define TL_stories_incrementStoryViews       0xb2028afb
#define TL_messages_getMessagesViews         0x5784d3e1
#define TL_messages_getSponsoredMessages     0x9bd2f439
#define TL_channels_getSponsoredMessages     0xec210fbf

@implementation THFeatures

+ (NSArray<THFeature *> *)all {
    static NSArray *all;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        all = @[
            F(@"ghost.online", THSectionGhost, @"Скрыть «в сети»",
              @"Не отправлять account.updateStatus — последний визит замирает", NO,
              @[@(TL_account_updateStatus)]),
            F(@"ghost.read", THSectionGhost, @"Не читать сообщения",
              @"Собеседник не увидит двух галочек", YES,
              @[@(TL_messages_readHistory), @(TL_channels_readHistory),
                @(TL_messages_readEncryptedHistory), @(TL_messages_readDiscussion),
                @(TL_messages_readMentions), @(TL_messages_readReactions)]),
            F(@"ghost.contents", THSectionGhost, @"Не отмечать прослушанным",
              @"Голосовые и кружки остаются «непрослушанными»", YES,
              @[@(TL_messages_readMessageContents), @(TL_channels_readMessageContents)]),
            F(@"ghost.typing", THSectionGhost, @"Скрыть «печатает…»",
              @"Также «записывает голосовое», «выбирает стикер» и т.д.", NO,
              @[@(TL_messages_setTyping), @(TL_messages_setEncryptedTyping)]),
            F(@"ghost.stories", THSectionGhost, @"Анонимные истории",
              @"Вы не появитесь в списке просмотревших", YES,
              @[@(TL_stories_readStories), @(TL_stories_incrementStoryViews)]),
            F(@"privacy.views", THSectionPrivacy, @"Не накручивать просмотры",
              @"Каналы не засчитают просмотр (счётчики перестанут обновляться)", NO,
              @[@(TL_messages_getMessagesViews)]),
            F(@"ads.sponsored", THSectionAds, @"Убрать рекламу в каналах",
              @"Блокирует загрузку спонсорских сообщений", NO,
              @[@(TL_messages_getSponsoredMessages), @(TL_channels_getSponsoredMessages)]),
        ];
    });
    return all;
}

+ (NSArray<THFeature *> *)inSection:(NSString *)section {
    return [[self all] filteredArrayUsingPredicate:
            [NSPredicate predicateWithFormat:@"section == %@", section]];
}

+ (NSDictionary<NSNumber *, THFeature *> *)index {
    static NSDictionary *index;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (THFeature *f in [self all])
            for (NSNumber *c in f.constructors) d[c] = f;
        index = d;
    });
    return index;
}

+ (THFeature *)featureForConstructor:(uint32_t)constructor {
    return [self index][@(constructor)];
}

+ (NSString *)nameForConstructor:(uint32_t)constructor {
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @(TL_account_updateStatus): @"account.updateStatus",
            @(TL_messages_readHistory): @"messages.readHistory",
            @(TL_channels_readHistory): @"channels.readHistory",
            @(TL_messages_readEncryptedHistory): @"messages.readEncryptedHistory",
            @(TL_messages_readDiscussion): @"messages.readDiscussion",
            @(TL_messages_readMentions): @"messages.readMentions",
            @(TL_messages_readReactions): @"messages.readReactions",
            @(TL_messages_readMessageContents): @"messages.readMessageContents",
            @(TL_channels_readMessageContents): @"channels.readMessageContents",
            @(TL_messages_setTyping): @"messages.setTyping",
            @(TL_messages_setEncryptedTyping): @"messages.setEncryptedTyping",
            @(TL_stories_readStories): @"stories.readStories",
            @(TL_stories_incrementStoryViews): @"stories.incrementStoryViews",
            @(TL_messages_getMessagesViews): @"messages.getMessagesViews",
            @(TL_messages_getSponsoredMessages): @"messages.getSponsoredMessages",
            @(TL_channels_getSponsoredMessages): @"channels.getSponsoredMessages",
            @(0xedd4882a): @"updates.getState",
            @(0x19c2f763): @"updates.getDifference",
            @(0x03173d78): @"updates.getChannelDifference",
            @(0xa0f4cb4f): @"messages.getDialogs",
            @(0x4423e6c5): @"messages.getHistory",
            @(0xda9b0d0d): @"invokeWithLayer",
            @(0xc1cd5ea9): @"initConnection",
            @(0xc4f9186b): @"help.getConfig",
            @(0x0d91a548): @"users.getUsers",
            @(0xb60f5918): @"users.getFullUser",
        };
    });
    return names[@(constructor)];
}

@end
