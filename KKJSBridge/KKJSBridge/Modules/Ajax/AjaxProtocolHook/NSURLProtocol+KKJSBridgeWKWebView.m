//
//  NSURLProtocol+KKJSBridgeWKWebView.m
//  KKJSBridge
//
//  Created by karos li on 2020/6/20.
//

#import "NSURLProtocol+KKJSBridgeWKWebView.h"
#import <WebKit/WebKit.h>

//customSchemes
SEL KKJSBridge_WKWebView_RegisterSchemeSelector(void) {
    return NSSelectorFromString(@"registerSchemeForCustomProtocol:");
}

SEL KKJSBridge_WKWebView_UnregisterSchemeSelector(void) {
    return NSSelectorFromString(@"unregisterSchemeForCustomProtocol:");
}
// https://github.com/WebKit/webkit/blob/989f1ffc97f6b168687cbfc6f98d35880fdd29de/Source/WebKit/UIProcess/API/Cocoa/WKBrowsingContextController.mm
Class KKJSBridge_WKWebView_ContextControllerClass(void) {
    
    //注册scheme
    Class cls = NSClassFromString(@"WKBrowsingContextController");
    SEL selector = KKJSBridge_WKWebView_RegisterSchemeSelector();
    if ([cls respondsToSelector:selector]) {
        return cls;
    } else {
        NSLog(@"browsingContextController method not found or inaccessible.");
        return nil;
    }
}

@implementation NSURLProtocol (KKJSBridgeWKWebView)

+ (void)KKJSBridgeRegisterScheme:(NSString *)scheme {
    Class cls = KKJSBridge_WKWebView_ContextControllerClass();
    SEL sel = KKJSBridge_WKWebView_RegisterSchemeSelector();
    if ([(id)cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(id)cls performSelector:sel withObject:scheme];
#pragma clang diagnostic pop
    }
}

+ (void)KKJSBridgeUnregisterScheme:(NSString *)scheme {
    Class cls = KKJSBridge_WKWebView_ContextControllerClass();
    SEL sel = KKJSBridge_WKWebView_UnregisterSchemeSelector();
    if ([(id)cls respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [(id)cls performSelector:sel withObject:scheme];
#pragma clang diagnostic pop
    }
}

@end
