#import "KKJSBridgeFormBodyStore.h"

static NSMapTable<NSString *, KKJSBridgeFormBodyStore *> *stores;
@interface KKJSBridgeFormBodyStore ()
@property (nonatomic) NSDictionary *configuration;
@property (nonatomic) NSMutableDictionary<NSString *, NSDictionary *> *entries;
@property (nonatomic) NSMutableDictionary<NSString *, NSNumber *> *used;
@end

@interface KKJSBridgeFormBodyWaiter : NSObject
@property (nonatomic) NSMutableURLRequest *request;
@property (nonatomic) NSString *token;
@property (nonatomic) NSTimeInterval deadline;
@property (nonatomic, copy) void (^completion)(NSMutableURLRequest *, NSError *);
- (void)tick;
- (void)cancel;
@end
@implementation KKJSBridgeFormBodyWaiter
- (void)cancel {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    if (!self.completion) return;
    self.completion = nil;
    [KKJSBridgeFormBodyStore discardToken:self.token];
}
- (void)tick {
    if (!self.completion) return;
    NSData *body = [KKJSBridgeFormBodyStore consumeToken:self.token request:self.request];
    if (body || NSProcessInfo.processInfo.systemUptime >= self.deadline) {
        void (^complete)(NSMutableURLRequest *, NSError *) = self.completion;
        self.completion = nil;
        if (body) {
            self.request.HTTPBody = body;
            [self.request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
            [self.request setValue:@(body.length).stringValue forHTTPHeaderField:@"Content-Length"];
            complete(self.request, nil);
        } else {
            [KKJSBridgeFormBodyStore discardToken:self.token];
            complete(nil, [NSError errorWithDomain:@"KKJSBridge.FormBody" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"Form could not be submitted. Reload the page and try again."}]);
        }
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self tick]; });
    }
}
@end

@implementation KKJSBridgeFormBodyStore
+ (dispatch_block_t)awaitRequest:(NSURLRequest *)request completion:(void (^)(NSMutableURLRequest *, NSError *))completion {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    KKJSBridgeFormBodyWaiter *waiter = [KKJSBridgeFormBodyWaiter new];
    waiter.request = [request mutableCopy];
    waiter.token = [self tokenInURL:request.URL] ?: @"";
    waiter.deadline = NSProcessInfo.processInfo.systemUptime + 2;
    waiter.completion = completion;
    [waiter tick];
    return ^{ [waiter cancel]; };
}
+ (void)initialize {
    if (self == KKJSBridgeFormBodyStore.class) stores = [NSMapTable strongToWeakObjectsMapTable];
}
static NSString *origin(NSURL *url) {
    if (![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length || url.user || url.password) return nil;
    NSString *host = url.host.lowercaseString;
    if ([host containsString:@":"] && ![host hasPrefix:@"["]) host = [NSString stringWithFormat:@"[%@]", host];
    return [NSString stringWithFormat:@"https://%@%@", host,
        url.port && url.port.integerValue != 443 ? [@":" stringByAppendingString:url.port.stringValue] : @""];
}
static BOOL matchesSource(NSArray *rules, NSURL *source) {
    NSString *sourceOrigin = origin(source);
    if (!sourceOrigin) return NO;
    NSString *sourcePath = [NSURLComponents componentsWithURL:source resolvingAgainstBaseURL:NO].percentEncodedPath;
    if (!sourcePath.length) sourcePath = @"/";
    for (NSDictionary *rule in rules) {
        NSString *ruleOrigin = rule[@"sourceOrigin"];
        if (([ruleOrigin isEqual:@"*"] || [sourceOrigin isEqual:ruleOrigin]) &&
            [sourcePath hasPrefix:rule[@"sourcePathPrefix"]]) return YES;
    }
    return NO;
}
- (instancetype)initWithRules:(NSArray *)rules {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    if (![rules isKindOfClass:NSArray.class] || !rules.count || rules.count > 64) return nil;
    NSMutableArray *normalized = [NSMutableArray array];
    for (NSDictionary *rule in rules) {
        if (![rule isKindOfClass:NSDictionary.class]) return nil;
        for (NSString *key in @[@"sourceOrigin", @"sourcePathPrefix"])
            if (![rule[key] isKindOfClass:NSString.class]) return nil;
        NSString *configuredOrigin = rule[@"sourceOrigin"];
        NSString *normalizedOrigin = nil;
        if ([configuredOrigin isEqual:@"*"]) {
            normalizedOrigin = @"*";
        } else {
            NSURL *source = [NSURL URLWithString:configuredOrigin];
            if (!origin(source) || source.query || source.fragment || source.path.length > 1) return nil;
            normalizedOrigin = origin(source);
        }
        if (![rule[@"sourcePathPrefix"] hasPrefix:@"/"] || ![rule[@"sourcePathPrefix"] hasSuffix:@"/"] ||
            [rule[@"sourcePathPrefix"] containsString:@"?"] || [rule[@"sourcePathPrefix"] containsString:@"#"]) return nil;
        NSDictionary *normalizedRule = @{@"sourceOrigin": normalizedOrigin, @"sourcePathPrefix": rule[@"sourcePathPrefix"]};
        if (![normalized containsObject:normalizedRule]) [normalized addObject:normalizedRule];
    }
    if ((self = [super init])) {
        _configuration = @{@"scope": NSUUID.UUID.UUIDString, @"rules": normalized};
        _entries = [NSMutableDictionary dictionary]; _used = [NSMutableDictionary dictionary];
        [stores setObject:self forKey:_configuration[@"scope"]];
    }
    return self;
}
- (void)prune {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    for (NSString *key in self.entries.allKeys)
        if ([self.entries[key][@"expiry"] doubleValue] <= now) [self.entries removeObjectForKey:key];
    for (NSString *key in self.used.allKeys)
        if (self.used[key].doubleValue <= now) [self.used removeObjectForKey:key];
}
+ (KKJSBridgeFormBodyStore *)storeForToken:(NSString *)token {
    if (![token isKindOfClass:NSString.class]) return nil;
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 2 || [parts[1] length] != 32 ||
        [parts[1] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) return nil;
    return [stores objectForKey:parts[0]];
}
- (BOOL)cacheParameters:(NSDictionary *)params sourceURL:(NSURL *)sourceURL {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    NSString *token = params[@"requestId"], *value = params[@"value"], *urlString = params[@"requestUrl"], *method = params[@"requestMethod"];
    NSURL *url = [urlString isKindOfClass:NSString.class] ? [NSURL URLWithString:urlString] : nil;
    [self prune];
    if ([KKJSBridgeFormBodyStore storeForToken:token] != self || self.used[token] || self.entries[token] ||
        self.entries.count + self.used.count >= 128 || ![value isKindOfClass:NSString.class] ||
        [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 65536 || ![method isEqual:@"POST"] ||
        url.fragment != nil || !matchesSource(self.configuration[@"rules"], sourceURL) ||
        ![origin(sourceURL) isEqual:origin(url)]) return NO;
    self.entries[token] = @{@"url": urlString, @"method": method, @"body": [value dataUsingEncoding:NSUTF8StringEncoding],
        @"expiry": @(NSProcessInfo.processInfo.systemUptime + 10)};
    // Do not retain the body in the timer block, nor keep a closed WebView alive.
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [weakSelf prune]; });
    return YES;
}
+ (NSString *)tokenInURL:(NSURL *)url {
    NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    // Only our appended, final parameter is recognized. Preserve the original query bytes.
    NSString *last = [c.percentEncodedQuery componentsSeparatedByString:@"&"].lastObject;
    NSString *prefix = @"KKJSBridge-FormBody=";
    NSString *token = [last hasPrefix:prefix] ? [[last substringFromIndex:prefix.length] stringByRemovingPercentEncoding] : nil;
    NSArray *parts = [token componentsSeparatedByString:@"."];
    if (parts.count != 2 || ![[NSUUID alloc] initWithUUIDString:parts[0]] || [parts[1] length] != 32 ||
        [parts[1] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) return nil;
    return token;
}
+ (NSData *)consumeToken:(NSString *)token request:(NSMutableURLRequest *)request {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    KKJSBridgeFormBodyStore *store = [self storeForToken:token];
    [store prune];
    NSDictionary *entry = store.entries[token];
    if (!entry || ![request.HTTPMethod isEqual:entry[@"method"]] || ![[self tokenInURL:request.URL] isEqual:token]) return nil;
    NSURLComponents *c = [NSURLComponents componentsWithURL:request.URL resolvingAgainstBaseURL:NO];
    NSRange separator = [c.percentEncodedQuery rangeOfString:@"&" options:NSBackwardsSearch];
    c.percentEncodedQuery = separator.location == NSNotFound ? nil : [c.percentEncodedQuery substringToIndex:separator.location];
    if (![c.URL.absoluteString isEqual:entry[@"url"]]) return nil;
    NSData *body = entry[@"body"];
    [self discardToken:token];
    request.URL = c.URL;
    return body;
}
+ (void)discardToken:(NSString *)token {
    NSAssert(NSThread.isMainThread, @"Main thread only");
    KKJSBridgeFormBodyStore *store = [self storeForToken:token];
    [store.entries removeObjectForKey:token];
    if (store && store.used.count < 256) store.used[token] = @(NSProcessInfo.processInfo.systemUptime + 10);
}
@end
