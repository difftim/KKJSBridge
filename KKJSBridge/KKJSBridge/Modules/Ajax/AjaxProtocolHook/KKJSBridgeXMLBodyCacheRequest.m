//
//  KKJSBridgeXMLBodyCacheRequest.m
//  KKJSBridge
//
//  Created by karos li on 2020/6/20.
//  Copyright © 2020 karosli. All rights reserved.
//

#import "KKJSBridgeXMLBodyCacheRequest.h"
#import "KKJSBridgeModuleRegister.h"
#import "KKJSBridgeEngine.h"
#import "KKJSBridgeAjaxURLProtocol.h"
#import "KKJSBridgeSafeDictionary.h"
#import "KKJSBridgeFormBodyStore.h"
#import <objc/runtime.h>
static char formBodyStoreKey;

static KKJSBridgeSafeDictionary *bodyCache;

@interface KKJSBridgeXMLBodyCacheRequest()<KKJSBridgeModule>
@property (nonatomic, copy) NSOperationQueue *queue;
@end

@implementation KKJSBridgeXMLBodyCacheRequest

+ (void)initialize {
    if (self == [KKJSBridgeXMLBodyCacheRequest self]) {
        [NSURLProtocol registerClass:KKJSBridgeAjaxURLProtocol.class];
        bodyCache = [KKJSBridgeSafeDictionary new];
    }
}

+ (nonnull NSString *)moduleName {
    return @"ajax";
}

+ (BOOL)isSingleton {
    return true;
}

- (instancetype)initWithEngine:(KKJSBridgeEngine *)engine context:(id)context {
    if (self = [super init]) {
        _queue = [NSOperationQueue new];
        _queue.maxConcurrentOperationCount = 5;
    }
    
    return self;
}

- (NSOperationQueue *)methodInvokeQueue {
    return self.queue;
}

/**
  {
     //请求唯一id
     requestId,
     //当前 href url
     requestHref,
     //请求 Url
     requestUrl,
     //body 类型
     bodyType
     //表单编码类型
     formEnctype
     //body 具体值
     value
 }
 */
- (void)cacheAJAXBody:(KKJSBridgeEngine *)engine params:(NSDictionary *)params responseCallback:(void (^)(NSDictionary *responseData))responseCallback {
    NSString *requestId = params[@"requestId"];
    bodyCache[requestId] = params;
    
    if (responseCallback && requestId) {
        responseCallback(@{@"requestId": requestId,
                           @"requestUrl": params[@"requestUrl"] ? params[@"requestUrl"] : @""
                         });
    }
}

// The store lifetime and policy belong to this engine, never to the singleton module.
+ (BOOL)installFormBodyRecoveryForEngine:(KKJSBridgeEngine *)engine rules:(NSArray *)rules {
    NSAssert(NSThread.isMainThread, @"Install before navigation on main thread");
    if (objc_getAssociatedObject(engine, &formBodyStoreKey)) return NO;
    KKJSBridgeFormBodyStore *store = [[KKJSBridgeFormBodyStore alloc] initWithRules:rules];
    NSURL *resource = [[NSBundle bundleForClass:self] URLForResource:@"KKJSBridgeFormBodyRecovery" withExtension:@"js"];
    NSString *source = resource ? [NSString stringWithContentsOfURL:resource encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!store || !source || !engine.webView) return NO;
    NSData *json = [NSJSONSerialization dataWithJSONObject:store.configuration options:0 error:nil];
    NSString *config = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *script = [source stringByAppendingFormat:@"\nwindow.KKJSBridgeInstallFormBodyRecovery(%@);", config];
    [engine.webView.configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    objc_setAssociatedObject(engine, &formBodyStoreKey, store, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

- (void)cacheFormBody:(KKJSBridgeEngine *)engine params:(NSDictionary *)params responseCallback:(void (^)(NSDictionary *))responseCallback {
    dispatch_async(dispatch_get_main_queue(), ^{
        KKJSBridgeFormBodyStore *store = objc_getAssociatedObject(engine, &formBodyStoreKey);
        NSURL *sourceURL = [params[@"__nativeFormSourceURL"] isKindOfClass:NSURL.class] ? params[@"__nativeFormSourceURL"] : nil;
        BOOL cached = [store cacheParameters:params sourceURL:sourceURL];
        NSLog(@"[KK-FormBody] stage=%@ bodyBytes=%lu", cached ? @"cacheStored" : @"cacheRejected",
            (unsigned long)(cached ? [params[@"value"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] : 0));
        if (responseCallback) responseCallback(@{@"cached": @(cached)});
    });
}

+ (NSDictionary *)getRequestBody:(NSString *)requestId {
    if (!requestId) {
        return nil;
    }
    
    return bodyCache[requestId];
}

+ (void)deleteRequestBody:(NSString *)requestId {
    if (!requestId) {
        return;
    }
    
    return [bodyCache removeObjectForKey:requestId];
}

@end
