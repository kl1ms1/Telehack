#import "THDiag.h"
#import "THCompat.h"
#import <Security/Security.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <fcntl.h>
#import <unistd.h>

// Raw TCP connect to host:port with a timeout. Returns 0 on success, else errno.
static int THTcpProbe(const char *host, int port, int timeoutSec) {
    struct addrinfo hints = {0}, *res = NULL;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    char portStr[8]; snprintf(portStr, sizeof(portStr), "%d", port);
    int g = getaddrinfo(host, portStr, &hints, &res);
    if (g != 0 || !res) return -1000 - g;  // DNS failure
    int result = -1;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) { result = errno; continue; }
        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        int c = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (c == 0) { close(fd); result = 0; break; }
        if (errno == EINPROGRESS) {
            fd_set wset; FD_ZERO(&wset); FD_SET(fd, &wset);
            struct timeval tv = { timeoutSec, 0 };
            int s = select(fd + 1, NULL, &wset, NULL, &tv);
            if (s > 0) {
                int err = 0; socklen_t len = sizeof(err);
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len);
                result = err;  // 0 == connected
                close(fd);
                if (err == 0) break; else continue;
            } else {
                result = ETIMEDOUT; close(fd); continue;
            }
        }
        result = errno; close(fd);
    }
    freeaddrinfo(res);
    return result;
}

void THDiagRun(void (^completion)(NSString *report)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSMutableString *r = [NSMutableString string];

        // 1) App group — Telegram derives it as group.<bundleId>. Check BOTH the
        //    derived one (what Telegram actually asks for) and the original, and
        //    report whether we got a REAL container or just THCompat's fallback.
        NSString *bid = [NSBundle mainBundle].bundleIdentifier ?: @"?";
        NSString *derived = [@"group." stringByAppendingString:bid];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *gD = [fm containerURLForSecurityApplicationGroupIdentifier:derived];
        NSURL *gO = [fm containerURLForSecurityApplicationGroupIdentifier:@"group.ph.telegra.Telegraph"];
        NSString *(^state)(NSURL *) = ^NSString *(NSURL *u){
            if (!u) return @"НЕТ (nil)";
            return [u.path containsString:@"TeleHackGroup"] ? @"запасной (THCompat)" : @"НАСТОЯЩИЙ ✅";
        };
        [r appendFormat:@"Bundle ID: %@\n", bid];
        [r appendFormat:@"App Group %@: %@\n", derived, state(gD)];
        [r appendFormat:@"App Group group.ph.telegra.Telegraph: %@\n", state(gO)];

        // 2) Raw TCP to a Telegram datacenter IP (MTProto path)
        int dc = THTcpProbe("149.154.167.51", 443, 6);
        [r appendFormat:@"TCP к серверу Telegram (DC IP:443): %@\n",
            dc == 0 ? @"OK ✅" : [NSString stringWithFormat:@"ошибка %d ❌", dc]];

        // 3) DNS + TCP to telegram.org
        int web = THTcpProbe("telegram.org", 443, 6);
        [r appendFormat:@"TCP к telegram.org:443 (DNS+connect): %@\n",
            web == 0 ? @"OK ✅" : [NSString stringWithFormat:@"ошибка %d ❌", web]];

        // 4) Full HTTPS request
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSString *httpLine = @"HTTPS: таймаут ❌";
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        cfg.timeoutIntervalForRequest = 8;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
        NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://core.telegram.org/"]
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                if (err) httpLine = [NSString stringWithFormat:@"HTTPS: %@ ❌", err.localizedDescription];
                else httpLine = [NSString stringWithFormat:@"HTTPS core.telegram.org: %ld ✅",
                                 (long)((NSHTTPURLResponse *)resp).statusCode];
                dispatch_semaphore_signal(sem);
            }];
        [task resume];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
        [r appendFormat:@"%@\n", httpLine];

        // 5) External IP + country — tells us if the copy is going through the VPN
        dispatch_semaphore_t sem2 = dispatch_semaphore_create(0);
        __block NSString *ipLine = @"Внешний IP: не удалось узнать";
        NSURLSessionDataTask *t2 = [session dataTaskWithURL:[NSURL URLWithString:@"https://ipapi.co/json/"]
            completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
                if (data) {
                    NSDictionary *j = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if ([j isKindOfClass:[NSDictionary class]]) {
                        ipLine = [NSString stringWithFormat:@"Внешний IP: %@ (%@, %@)",
                                  j[@"ip"] ?: @"?", j[@"country_name"] ?: j[@"country"] ?: @"?", j[@"org"] ?: @""];
                    }
                }
                dispatch_semaphore_signal(sem2);
            }];
        [t2 resume];
        dispatch_semaphore_wait(sem2, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
        [r appendFormat:@"%@\n", ipLine];

        // 6) Keychain access — a resigned copy often loses its keychain group,
        // which breaks MTProto's secure connection and looks like "no internet".
        NSDictionary *item = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                (__bridge id)kSecAttrService: @"telehack.probe",
                                (__bridge id)kSecAttrAccount: @"probe",
                                (__bridge id)kSecValueData: [@"x" dataUsingEncoding:NSUTF8StringEncoding] };
        SecItemDelete((__bridge CFDictionaryRef)item);
        OSStatus kcAdd = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        NSDictionary *q = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                             (__bridge id)kSecAttrService: @"telehack.probe",
                             (__bridge id)kSecAttrAccount: @"probe",
                             (__bridge id)kSecReturnData: (__bridge id)kCFBooleanTrue };
        CFTypeRef out = NULL;
        OSStatus kcGet = SecItemCopyMatching((__bridge CFDictionaryRef)q, &out);
        if (out) CFRelease(out);
        SecItemDelete((__bridge CFDictionaryRef)item);
        NSString *(^kc)(OSStatus) = ^NSString *(OSStatus st){
            if (st == errSecSuccess) return @"OK ✅";
            if (st == errSecMissingEntitlement) return @"НЕТ ПРАВ (-34018) ❌ — вот причина!";
            return [NSString stringWithFormat:@"код %d", (int)st];
        };
        [r appendFormat:@"Keychain запись: %@\n", kc(kcAdd)];
        [r appendFormat:@"Keychain чтение: %@\n", kc(kcGet)];

        [r appendString:@"\nerrno: 60=таймаут, 61=отказ, 65=нет маршрута, 50=сеть недоступна, 1=нет прав"];

        dispatch_async(dispatch_get_main_queue(), ^{ completion(r); });
    });
}
