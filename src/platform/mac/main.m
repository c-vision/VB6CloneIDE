#import <Cocoa/Cocoa.h>

#import "VBAppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        VBAppDelegate *delegate = [[VBAppDelegate alloc] init];
        if (argc > 1) {
            NSString *path = [NSString stringWithUTF8String:argv[1]];
            if (path.length > 0 && ![path hasPrefix:@"-"]) delegate.startupPath = path;
        }
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
