#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Foundation-only state owned by one bridge engine. All access is on the main thread.
@interface KKJSBridgeFormBodyStore : NSObject
@property (nonatomic, readonly) NSDictionary *configuration;
- (nullable instancetype)initWithRules:(NSArray<NSDictionary<NSString *, NSString *> *> *)rules;
- (BOOL)cacheParameters:(NSDictionary *)params sourceURL:(nullable NSURL *)sourceURL;
+ (nullable NSString *)tokenInURL:(NSURL *)url;
+ (nullable NSData *)consumeToken:(NSString *)token request:(NSMutableURLRequest *)request;
// Starts a bounded asynchronous wait; returned block cancels without a completion callback.
+ (dispatch_block_t)awaitRequest:(NSURLRequest *)request
                     completion:(void (^)(NSMutableURLRequest * _Nullable request, NSError * _Nullable error))completion;
+ (void)discardToken:(NSString *)token;
@end
NS_ASSUME_NONNULL_END
