//
//  KKJSBridgeMessage.m
//  KKJSBridge
//
//  Created by karos li on 2019/7/22.
//  Copyright © 2019 karosli. All rights reserved.
//

#import "KKJSBridgeMessage.h"

@implementation KKJSBridgeMessage

- (void)dealloc {
    // 确保 completionHandler 被调用，避免 iOS 抛出异常
    if (self.callback) {
        // 必须在主线程调用 WKWebView 相关的 completionHandler
        void (^callback)(NSDictionary * _Nullable) = self.callback;
        self.callback = nil;  // 防止重复调用

        if ([NSThread isMainThread]) {
            callback(nil);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                callback(nil);
            });
        }
    }
}

@end

