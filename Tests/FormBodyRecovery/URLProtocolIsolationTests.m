#import <Foundation/Foundation.h>
#import "KKJSBridgeAjaxURLProtocol.h"
#import "KKJSBridgeXMLBodyCacheRequest.h"
#import "KKJSBridgeEngine.h"
#import "KKWebViewCookieManager.h"

// Replace only external collaborators. Protocol, both stores and body serializer are production code.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
@implementation KKJSBridgeConfig
static __weak id<KKJSBridgeAjaxDelegateManager> manager;
+ (id<KKJSBridgeAjaxDelegateManager>)ajaxDelegateManager { return manager; }
+ (void)setAjaxDelegateManager:(id<KKJSBridgeAjaxDelegateManager>)value { manager = value; }
@end
@implementation KKWebViewCookieManager
+ (void)syncRequestCookie:(NSMutableURLRequest *)request {}
@end
#pragma clang diagnostic pop
@implementation KKJSBridgeCustomInterceptRequest
+ (instancetype)shareInstance { static id instance; if (!instance) instance = [self new]; return instance; }
- (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
@end
@interface KKJSBridgeXMLBodyCacheRequest (TestEntry)
- (void)cacheAJAXBody:(id)engine params:(NSDictionary *)params responseCallback:(void (^)(NSDictionary *))callback;
@end
@interface TestTask : NSObject
@property BOOL resumed;
@property BOOL canceled;
@end
@implementation TestTask
- (void)resume { self.resumed = YES; }
- (void)cancel { self.canceled = YES; }
@end
@interface TestManager : NSObject <KKJSBridgeAjaxDelegateManager>
@property NSURLRequest *sent;
@property TestTask *task;
@property (copy) dispatch_block_t onCreate;
@end
@implementation TestManager
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request callbackDelegate:(NSObject<KKJSBridgeAjaxDelegate> *)delegate {
    self.sent = request; self.task = [TestTask new];
    if (self.onCreate) self.onCreate();
    return (id)self.task;
}
@end
@interface TestClient : NSObject <NSURLProtocolClient>
@property NSMutableArray *events;
@end
@implementation TestClient
- (instancetype)init { if ((self = [super init])) _events = [NSMutableArray new]; return self; }
- (void)URLProtocol:(NSURLProtocol *)p didReceiveResponse:(NSURLResponse *)r cacheStoragePolicy:(NSURLCacheStoragePolicy)s { [self.events addObject:@"response"]; }
- (void)URLProtocol:(NSURLProtocol *)p didLoadData:(NSData *)d { [self.events addObject:d]; }
- (void)URLProtocolDidFinishLoading:(NSURLProtocol *)p { [self.events addObject:@"finish"]; }
- (void)URLProtocol:(NSURLProtocol *)p didFailWithError:(NSError *)e { [self.events addObject:e]; }
- (void)URLProtocol:(NSURLProtocol *)p wasRedirectedToRequest:(NSURLRequest *)r redirectResponse:(NSURLResponse *)s {}
- (void)URLProtocol:(NSURLProtocol *)p cachedResponseIsValid:(NSCachedURLResponse *)r {}
- (void)URLProtocol:(NSURLProtocol *)p didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)c {}
- (void)URLProtocol:(NSURLProtocol *)p didCancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)c {}
@end
@interface ScriptRecorder : NSObject
@property NSMutableArray *scripts;
@end
@implementation ScriptRecorder
- (instancetype)init { if ((self = [super init])) _scripts = [NSMutableArray new]; return self; }
- (void)evaluateJavaScript:(NSString *)script completionHandler:(id)handler { [self.scripts addObject:script]; }
@end
static int checks;
static void check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"FAIL: %@", message); exit(1); } checks++; }
static KKJSBridgeAjaxURLProtocol *protocol(NSString *url, TestClient *client) {
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    r.HTTPMethod = @"POST"; r.HTTPBody = [@"original" dataUsingEncoding:NSUTF8StringEncoding];
    return [[KKJSBridgeAjaxURLProtocol alloc] initWithRequest:r cachedResponse:nil client:client];
}
int main(void) { @autoreleasepool {
    TestManager *network = [TestManager new]; KKJSBridgeConfig.ajaxDelegateManager = network;
    KKJSBridgeXMLBodyCacheRequest *cache = [KKJSBridgeXMLBodyCacheRequest new];
    TestClient *client = [TestClient new];
    [cache cacheAJAXBody:nil params:@{@"requestId":@"123", @"bodyType":@"String", @"value":@"a=one%20two&b=+"} responseCallback:nil];
    KKJSBridgeAjaxURLProtocol *p = protocol(@"https://example.test/api?x=1&KKJSBridge-RequestId=123", client);
    [p startLoading];
    check(network.task.resumed, @"legacy body dispatch remains synchronous");
    check([network.sent.HTTPBody isEqual:[@"a=one%20two&b=+" dataUsingEncoding:NSUTF8StringEncoding]], @"actual legacy cache and serializer restore bytes");
    check([network.sent.URL.absoluteString isEqual:@"https://example.test/api?x=1"], @"legacy marker removed");
    check(![KKJSBridgeAjaxURLProtocol canInitWithRequest:network.sent], @"recursion marker retained");
    [p stopLoading];
    check(network.task.canceled && ![KKJSBridgeXMLBodyCacheRequest getRequestBody:@"123"], @"legacy cancellation cancels task and removes body");
    check(![[p valueForKey:@"formBodyStopped"] boolValue] && ![p valueForKey:@"cancelFormBodyWait"], @"legacy cancellation never enters form state");

    p = protocol(@"https://example.test/api?KKJSBridge-RequestId=456", client);
    [p startLoading];
    check(network.task.resumed && [network.sent.HTTPBody isEqual:p.request.HTTPBody], @"cache miss preserves original body without waiting");
    ScriptRecorder *web = [ScriptRecorder new];
    id<KKJSBridgeAjaxDelegate> delegate = (id)p;
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:network.sent.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"text/event-stream"}];
    NSData *chunk = [@"data: hello\n\n" dataUsingEncoding:NSUTF8StringEncoding];
    [delegate JSBridgeAjax:delegate didReceiveResponse:response webView:(id)web];
    [delegate JSBridgeAjax:delegate didReceiveData:chunk webView:(id)web];
    [delegate JSBridgeAjax:delegate didCompleteWithError:nil webView:(id)web];
    check([client.events isEqual:@[@"response",chunk,@"finish"]], @"SSE native forwarding order and bytes preserved");
    check(web.scripts.count == 3 && [web.scripts[0] containsString:@"_KKJSBridgeSSEBegin"] && [web.scripts[1] containsString:@"_KKJSBridgeSSEPush('456'"] && [web.scripts[2] containsString:@"_KKJSBridgeSSEEnd('456',false)"], @"SSE JS forwarding preserves request ID and order");

    // Cancellation during delegate task creation must not acquire new form-only semantics.
    p = protocol(@"https://example.test/plain", client);
    __weak KKJSBridgeAjaxURLProtocol *weakProtocol = p;
    network.onCreate = ^{ [weakProtocol stopLoading]; };
    [p startLoading];
    check(network.task.resumed && !network.task.canceled, @"unmarked request retains existing task-creation cancellation behavior");
    network.onCreate = nil; network.sent = nil;
    p = protocol(@"https://example.test/api?KKJSBridge-FormBody=11111111-1111-4111-8111-111111111111.00000000000000000000000000000001", client);
    [p stopLoading]; [p startLoading];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check([[p valueForKey:@"formBodyStopped"] boolValue] && !network.sent, @"form canceled before queued start never sends");
    NSLog(@"PASS: %d URLProtocol isolation checks", checks);
} return 0; }
