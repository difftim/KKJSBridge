#import <Foundation/Foundation.h>
#import "KKJSDialogCompletion.h"

// Mirrors how KKWebView uses KKJSDialogCompletion: WebKit throws if a dialog completion handler
// is released uncalled or called twice, so every scenario must end with exactly one answer.
static int checks;
static void check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL %@", name); exit(1); } checks++; }

int main(void) {
    @autoreleasepool {
        // Tapped button: the chosen answer runs once and the fallback never runs.
        __block NSMutableArray<NSString *> *answers = [NSMutableArray array];
        @autoreleasepool {
            KKJSDialogCompletion *completion = [[KKJSDialogCompletion alloc] initWithFallback:^{ [answers addObject:@"fallback"]; }];
            [completion completeWithBlock:^{ [answers addObject:@"confirm"]; }];
            [completion completeWithBlock:^{ [answers addObject:@"cancel"]; }];
        }
        check([answers isEqualToArray:@[@"confirm"]], @"first answer wins, later answers and fallback are ignored");

        // Alert torn down without a tap: the fallback answers on dealloc.
        answers = [NSMutableArray array];
        @autoreleasepool {
            __unused KKJSDialogCompletion *completion = [[KKJSDialogCompletion alloc] initWithFallback:^{ [answers addObject:@"fallback"]; }];
        }
        check([answers isEqualToArray:@[@"fallback"]], @"unanswered dialog falls back exactly once on dealloc");

        // Alert retained by an action block and released later, as UIAlertController does.
        answers = [NSMutableArray array];
        void (^actionHandler)(void);
        @autoreleasepool {
            KKJSDialogCompletion *completion = [[KKJSDialogCompletion alloc] initWithFallback:^{ [answers addObject:@"fallback"]; }];
            actionHandler = ^{ [completion completeWithBlock:^{ [answers addObject:@"confirm"]; }]; };
        }
        check(answers.count == 0, @"fallback waits while an action block still owns the completion");
        @autoreleasepool { actionHandler = nil; }
        check([answers isEqualToArray:@[@"fallback"]], @"releasing the last action block answers with the fallback");
    }
    NSLog(@"dialog completion: %d checks passed", checks);
    return 0;
}
