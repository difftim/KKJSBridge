//
//  KKJSDialogCompletion.h
//  KKJSBridge
//
//  Created by Jaymin on 2026/11/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Guarantees that a WKUIDelegate JavaScript dialog completion handler runs exactly once.

 WebKit raises NSInternalInconsistencyException when a dialog completion handler is released
 without being called, and when it is called twice. A native alert can be torn down without any
 button being tapped (another controller dismisses it, or it is deallocated with its presenter),
 so the handler must not live only inside the alert's action blocks.

 Every path that answers the dialog goes through -completeWithBlock:. If none has run when this
 object is deallocated, the fallback block answers the dialog with its cancel value instead.
 Capture this object strongly in the alert's action blocks so it lives exactly as long as the alert.
 */
@interface KKJSDialogCompletion : NSObject

- (instancetype)init NS_UNAVAILABLE;

/// @param fallback Answers the dialog with its cancel value; runs on dealloc if nothing completed it.
- (instancetype)initWithFallback:(void (^)(void))fallback NS_DESIGNATED_INITIALIZER;

/// Runs `block` if the dialog has not been answered yet; later calls are ignored.
- (void)completeWithBlock:(void (NS_NOESCAPE ^)(void))block;

@end

NS_ASSUME_NONNULL_END
