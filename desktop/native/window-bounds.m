#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
int main(void) {
    @autoreleasepool {
        NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
        NSMutableArray *result = [NSMutableArray array];
        for (NSDictionary *window in windows) {
            if ([window[(id)kCGWindowLayer] intValue] != 0 || [window[(id)kCGWindowAlpha] doubleValue] <= 0) continue;
            CGRect rect;
            if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(id)kCGWindowBounds], &rect) || rect.size.width < 20 || rect.size.height < 20) continue;
            [result addObject:@{@"x":@(rect.origin.x),@"y":@(rect.origin.y),@"width":@(rect.size.width),@"height":@(rect.size.height),@"pid":window[(id)kCGWindowOwnerPID] ?: @0}];
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if (!data) return 1;
        fwrite(data.bytes, 1, data.length, stdout);
    }
    return 0;
}
