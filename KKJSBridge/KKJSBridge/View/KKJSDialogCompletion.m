//
//  KKJSDialogCompletion.m
//  KKJSBridge
//
//  Created by Jaymin on 2026/11/25.
//

#import "KKJSDialogCompletion.h"

@interface KKJSDialogCompletion ()

/// Cleared once the dialog is answered, so neither a second answer nor the fallback can run.
@property (nonatomic, copy, nullable) void (^fallback)(void);

@end

@implementation KKJSDialogCompletion

- (instancetype)initWithFallback:(void (^)(void))fallback {
    self = [super init];
    if (self) {
        _fallback = [fallback copy];
    }
    return self;
}

- (void)completeWithBlock:(void (NS_NOESCAPE ^)(void))block {
    if (!self.fallback) {
        return;
    }
    self.fallback = nil;
    block();
}

- (void)dealloc {
    // WKUIDelegate callbacks and their UIAlertController teardown both run on the main thread,
    // which is where WebKit requires the completion handler to be called.
    if (_fallback) {
        void (^fallback)(void) = _fallback;
        _fallback = nil;
        fallback();
    }
}

@end
