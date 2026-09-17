#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface CLRemoteDelegate : NSObject <NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate>
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

    self.window.title = @"CL Ableton Remote";
    self.window.minSize = NSMakeSize(460, 700);

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:frame configuration:config];
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    self.window.contentView = self.webView;
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSString *urlString = @"http://127.0.0.1:5050/";
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;

    if (arguments.count > 1) {
        NSString *candidate = arguments[1];

        if ([candidate hasPrefix:@"http://127.0.0.1:5050/"] ||
            [candidate hasPrefix:@"http://localhost:5050/"]) {
            urlString = candidate;
        }
    }

    NSURL *url = [NSURL URLWithString:urlString];
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


- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;

    if (!url) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    NSString *host = url.host.lowercaseString ?: @"";
    NSNumber *port = url.port;

    BOOL isLocalHost =
        [host isEqualToString:@"127.0.0.1"] ||
        [host isEqualToString:@"localhost"];

    BOOL isCLRemote =
        isLocalHost &&
        (!port || port.integerValue == 5050) &&
        ([url.scheme.lowercaseString isEqualToString:@"http"] ||
         [url.scheme.lowercaseString isEqualToString:@"https"]);

    if (isCLRemote) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    if ([NSWorkspace.sharedWorkspace openURL:url]) {
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyCancel);
}

- (WKWebView *)webView:(WKWebView *)webView
createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
   forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    (void)configuration;
    (void)windowFeatures;

    if (navigationAction.targetFrame == nil) {
        [webView loadRequest:navigationAction.request];
    }

    return nil;
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
