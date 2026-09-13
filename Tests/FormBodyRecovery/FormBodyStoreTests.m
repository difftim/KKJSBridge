#import <Foundation/Foundation.h>
#import "KKJSBridgeFormBodyStore.h"
static int checks;
static void check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@",name); exit(1); } checks++; }
static NSDictionary *rule(void) { return @{@"sourceOrigin":@"https://forms.example:443", @"sourcePathPrefix":@"/pages/"}; }
static NSString *token(KKJSBridgeFormBodyStore *s, int index) { return [NSString stringWithFormat:@"%@.%032x",s.configuration[@"scope"],index]; }
static NSDictionary *params(NSString *t, NSString *url) { return @{@"requestId":t,@"requestUrl":url,@"requestMethod":@"POST",@"value":@"token=dummy%2B&repeat=a&repeat=b"}; }
static NSMutableURLRequest *request(NSString *t, NSString *url) {
 NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:[url stringByAppendingFormat:@"%@KKJSBridge-FormBody=%@",[url containsString:@"?"]?@"&":@"?",t]]]; r.HTTPMethod=@"POST";return r;
}
int main(void) { @autoreleasepool {
 NSURL *source=[NSURL URLWithString:@"https://forms.example/pages/login"];
 KKJSBridgeFormBodyStore *a=[[KKJSBridgeFormBodyStore alloc] initWithRules:@[rule()]];
 KKJSBridgeFormBodyStore *b=[[KKJSBridgeFormBodyStore alloc] initWithRules:@[rule()]];
 check(a && b,@"valid policies");
 check([a.configuration[@"rules"][0][@"sourceOrigin"] isEqual:@"https://forms.example"],@"normalize default port for both JS and native");
 NSDictionary *legacy=@{@"sourceOrigin":@"https://forms.example",@"sourcePathPrefix":@"/pages/",@"targetOrigin":@"https://api.example",@"targetPath":@"/submit"};
 KKJSBridgeFormBodyStore *legacyStore=[[KKJSBridgeFormBodyStore alloc] initWithRules:@[legacy,legacy]];
 check([legacyStore.configuration[@"rules"] count] == 1 && !legacyStore.configuration[@"rules"][0][@"targetPath"],@"legacy target fields collapse to one source rule");
 NSString *ta=token(a,1),*tb=token(b,1),*url=@"https://forms.example/submit?a=one%20two&a=%2f&plus=+&flag&empty=";
 check(![ta isEqual:tb],@"window namespaces even with same nonce");
 check(![b cacheParameters:params(ta,url) sourceURL:source],@"cross-window cache rejected");
 check([a cacheParameters:params(ta,url) sourceURL:source],@"allowed source/target and query");
 check(![a cacheParameters:params(ta,url) sourceURL:source],@"duplicate cache cannot overwrite");
 NSMutableURLRequest *wrong=request(ta,@"https://forms.example/submit?changed=1");
 check(![KKJSBridgeFormBodyStore consumeToken:ta request:wrong],@"target query mismatch rejected");
 NSMutableURLRequest *right=request(ta,url);NSData *body=[KKJSBridgeFormBodyStore consumeToken:ta request:right];
 check(body.length>0 && [right.URL.absoluteString isEqual:url],@"exact query bytes preserved");
 check(![KKJSBridgeFormBodyStore consumeToken:ta request:request(ta,url)],@"one-time consumption");
 check(![a cacheParameters:params(ta,url) sourceURL:source],@"consumed token cannot be recached");
 check([b cacheParameters:params(tb,url) sourceURL:source],@"second window independent");
 check([KKJSBridgeFormBodyStore consumeToken:tb request:request(tb,url)] != nil,@"second window consumption");
 for (NSString *bad in @[@"https://forms.example.evil/pages/login",@"http://forms.example/pages/login",@"https://forms.example/other/",@"https://forms.example/pagesEvil/",@"https://forms.example:444/pages/login"]) {
  check(![a cacheParameters:params(token(a,2),url) sourceURL:[NSURL URLWithString:bad]],@"source policy rejection");
 }
 NSString *dynamic=token(a,2),*dynamicURL=@"https://forms.example/new/endpoint";
 check([a cacheParameters:params(dynamic,dynamicURL) sourceURL:source],@"new same-origin target needs no policy update");
 NSMutableURLRequest *wrongVerb=request(dynamic,dynamicURL);wrongVerb.HTTPMethod=@"PUT";
 check(![KKJSBridgeFormBodyStore consumeToken:dynamic request:wrongVerb],@"dynamic target method remains exactly bound");
 check([KKJSBridgeFormBodyStore consumeToken:dynamic request:request(dynamic,dynamicURL)] != nil,@"dynamic target remains exactly bound");
 check(![a cacheParameters:params(token(a,9),@"https://api.example/submit") sourceURL:source],@"cross-origin target rejected");
 check(![a cacheParameters:params(token(a,9),@"https://user@forms.example/submit") sourceURL:source],@"URL credentials rejected");
 NSMutableDictionary *wrongMethod=[params(token(a,9),@"https://forms.example/submit") mutableCopy];wrongMethod[@"requestMethod"]=@"GET";
 check(![a cacheParameters:wrongMethod sourceURL:source],@"non-POST cache rejected");
 NSMutableDictionary *oversize=[params(token(a,2),url) mutableCopy];oversize[@"value"]=[@"a" stringByPaddingToLength:65537 withString:@"a" startingAtIndex:0];
 check(![a cacheParameters:oversize sourceURL:source],@"size limit");
 NSString *canceled=token(a,3);[KKJSBridgeFormBodyStore discardToken:canceled];
 check(![a cacheParameters:params(canceled,url) sourceURL:source],@"late body after cancellation/timeout rejected");
 NSString *emptyQuery=@"https://forms.example/submit?",*emptyToken=token(a,4);
 check([a cacheParameters:params(emptyToken,emptyQuery) sourceURL:source],@"empty query accepted");
 NSMutableURLRequest *empty=request(emptyToken,emptyQuery);
 check([KKJSBridgeFormBodyStore consumeToken:emptyToken request:empty] && [empty.URL.absoluteString isEqual:emptyQuery],@"empty query retained");
 NSString *closed;
 @autoreleasepool {
  KKJSBridgeFormBodyStore *temporary=[[KKJSBridgeFormBodyStore alloc] initWithRules:@[rule()]];
  closed=token(temporary,1);check([temporary cacheParameters:params(closed,url) sourceURL:source],@"temporary window cached");
 }
 check(![KKJSBridgeFormBodyStore consumeToken:closed request:request(closed,url)],@"closed window releases its cache");
 check(![[KKJSBridgeFormBodyStore alloc] initWithRules:@[]],@"empty policy disabled");
 NSMutableDictionary *invalid=[rule() mutableCopy];invalid[@"sourceOrigin"]=@"https://forms.example/path";
 check(![[KKJSBridgeFormBodyStore alloc] initWithRules:@[invalid]],@"origin cannot contain a page path");
 check(![KKJSBridgeFormBodyStore tokenInURL:[NSURL URLWithString:@"https://api.example/submit?KKJSBridge-FormBody=business-value"]],@"ordinary business parameter untouched");
 __block int delivered=0;
 NSString *delayed=token(a,6);
 [KKJSBridgeFormBodyStore awaitRequest:request(delayed,url) completion:^(NSMutableURLRequest *r, NSError *error) {
  check(!error && r.HTTPBody.length>0 && [r.URL.absoluteString isEqual:url],@"body arriving after navigation restores request");
  check([[r valueForHTTPHeaderField:@"Content-Length"] integerValue] == r.HTTPBody.length,@"restored length matches bytes"); delivered++;
 }];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
  check([a cacheParameters:params(delayed,url) sourceURL:source],@"delayed bridge arrival");
 });
 [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
 check(delivered==1,@"wait completes exactly once");
 NSString *missing=token(a,7);
 [KKJSBridgeFormBodyStore awaitRequest:request(missing,url) completion:^(NSMutableURLRequest *r, NSError *error) {
  check(!r && [error.domain isEqual:@"KKJSBridge.FormBody"],@"timeout does not produce a network request"); delivered++;
 }];
 NSString *stopped=token(a,8);
 dispatch_block_t cancel=[KKJSBridgeFormBodyStore awaitRequest:request(stopped,url) completion:^(NSMutableURLRequest *r, NSError *error) {
  check(NO,@"canceled wait must not invoke completion");
 }];cancel();
 check(![a cacheParameters:params(stopped,url) sourceURL:source],@"stopped request rejects late body");
 [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2.1]];
 check(delivered==2,@"timeout completes once");
 check(![a cacheParameters:params(missing,url) sourceURL:source],@"timed out request rejects late body");
 NSString *expiring=token(a,5);check([a cacheParameters:params(expiring,url) sourceURL:source],@"expiry setup");
 [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:10.1]];
 check(![KKJSBridgeFormBodyStore consumeToken:expiring request:request(expiring,url)],@"abandoned body expires");
 printf("PASS: %d native policy/cache checks\n",checks);
} return 0; }
