#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface CLRemoteDelegate : NSObject <NSApplicationDelegate, WKUIDelegate>
@property(nonatomic,strong) NSWindow *window;
@property(nonatomic,strong) WKWebView *webView;
@end

@implementation CLRemoteDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;

    NSRect frame = NSMakeRect(0, 0, 500, 900);

    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    self.window.title = @"Télécommande Ableton";
    self.window.minSize = NSMakeSize(460, 700);

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.UIDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.window.contentView = self.webView;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSURL *url = [NSURL URLWithString:@"http://127.0.0.1:5050/"];
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)webView:(WKWebView *)webView
    runJavaScriptConfirmPanelWithMessage:(NSString *)message
                        initiatedByFrame:(WKFrameInfo *)frame
                       completionHandler:(void (^)(BOOL result))completionHandler {
    (void)webView;
    (void)frame;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Télécommande CL Audio";
    alert.informativeText = message ?: @"Confirmer cette action ?";
    [alert addButtonWithTitle:@"Continuer"];
    [alert addButtonWithTitle:@"Annuler"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        completionHandler(response == NSAlertFirstButtonReturn);
    }];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

@end

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        CLRemoteDelegate *delegate = [[CLRemoteDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
