#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>

static NSString *EndpointName(MIDIEndpointRef endpoint) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || value == NULL) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    }
    return CFBridgingRelease(value) ?: @"";
}

static NSArray<NSString *> *EndpointNames(BOOL sources) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    ItemCount count = sources ? MIDIGetNumberOfSources() : MIDIGetNumberOfDestinations();
    for (ItemCount index = 0; index < count; index++) {
        MIDIEndpointRef endpoint = sources ? MIDIGetSource(index) : MIDIGetDestination(index);
        NSString *name = EndpointName(endpoint);
        if (name.length) [names addObject:name];
    }
    return names.array;
}

@interface CLNetworkDelegate : NSObject <NSApplicationDelegate, NSNetServiceBrowserDelegate>
@property NSWindow *window;
@property NSView *lamp;
@property NSTextField *headline;
@property NSTextField *detail;
@property NSTextField *sessionInfo;
@property NSTextField *lastTest;
@property NSPopUpButton *endpointMenu;
@property NSTextField *programField;
@property NSButton *testButton;
@property NSPopUpButton *targetMenu;
@property NSButton *connectButton;
@property NSTimer *timer;
@property NSNetServiceBrowser *serviceBrowser;
@property NSMutableOrderedSet<NSString *> *discoveredPeers;
@property NSString *localNetworkName;
@property BOOL peerInspectionRunning;
@property NSString *validatedEndpoint;
@property NSDate *validatedAt;
@end

@implementation CLNetworkDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.textColor = [NSColor colorWithWhite:0.76 alpha:1.0];
    label.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return label;
}

- (void)stylePopup:(NSPopUpButton *)popup accent:(NSColor *)accent {
    popup.font = [NSFont boldSystemFontOfSize:12.0];
    popup.contentTintColor = accent;
    popup.wantsLayer = YES;
    popup.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0].CGColor;
    popup.layer.cornerRadius = 8.0;
    popup.layer.borderWidth = 1.0;
    popup.layer.borderColor = [accent colorWithAlphaComponent:0.55].CGColor;
    for (NSMenuItem *item in popup.itemArray) {
        item.attributedTitle = [[NSAttributedString alloc] initWithString:item.title attributes:@{
            NSForegroundColorAttributeName: accent,
            NSFontAttributeName: [NSFont boldSystemFontOfSize:12.0]
        }];
    }
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = action;
    return button;
}

- (NSButton *)accentButton:(NSString *)title frame:(NSRect)frame action:(SEL)action color:(NSColor *)color {
    NSButton *button = [self button:title frame:frame action:action];
    button.bordered = NO;
    button.wantsLayer = YES;
    button.layer.backgroundColor = color.CGColor;
    button.layer.cornerRadius = 8.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [color blendedColorWithFraction:0.30 ofColor:NSColor.whiteColor].CGColor;
    button.layer.shadowColor = color.CGColor;
    button.layer.shadowOpacity = 0.22;
    button.layer.shadowRadius = 5.0;
    button.layer.shadowOffset = CGSizeMake(0, -1);
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSFontAttributeName: [NSFont boldSystemFontOfSize:12.0]
    }];
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 500)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI Network Assistant";
    self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.045 blue:0.060 alpha:1.0];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    NSView *content = self.window.contentView;

    NSView *header = [[NSView alloc] initWithFrame:NSMakeRect(16, 414, 448, 70)];
    header.wantsLayer = YES;
    header.layer.backgroundColor = [NSColor colorWithRed:0.018 green:0.023 blue:0.032 alpha:1.0].CGColor;
    header.layer.cornerRadius = 12.0;
    header.layer.borderWidth = 1.0;
    header.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor;
    [content addSubview:header];

    NSString *logoPath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"paradis_latin_logo.jpg"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    NSImageView *logoView = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 10, 155, 50)];
    logoView.image = logo;
    logoView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [header addSubview:logoView];
    NSTextField *appTitle = [self label:@"CL MIDI NETWORK ASSISTANT" frame:NSMakeRect(182, 32, 250, 22) size:13 bold:YES];
    NSTextField *appSubtitle = [self label:@"Connexion RTP · validation Yamaha" frame:NSMakeRect(182, 13, 250, 18) size:10 bold:NO];
    appSubtitle.textColor = [NSColor colorWithWhite:0.62 alpha:1.0];
    [header addSubview:appTitle];
    [header addSubview:appSubtitle];

    self.lamp = [[NSView alloc] initWithFrame:NSMakeRect(24, 338, 34, 34)];
    self.lamp.wantsLayer = YES;
    self.lamp.layer.cornerRadius = 17;
    [content addSubview:self.lamp];
    self.headline = [self label:@"Analyse de la connexion RTP…" frame:NSMakeRect(70, 346, 385, 25) size:17 bold:YES];
    self.detail = [self label:@"" frame:NSMakeRect(70, 320, 385, 22) size:11 bold:NO];
    [content addSubview:self.headline];
    [content addSubview:self.detail];

    [content addSubview:[self label:@"CIBLE RTP DISTANTE" frame:NSMakeRect(24, 278, 190, 20) size:10 bold:YES]];
    self.targetMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 244, 300, 30) pullsDown:NO];
    self.targetMenu.target = self;
    self.targetMenu.action = @selector(targetChanged:);
    [self.targetMenu addItemWithTitle:@"Recherche des correspondants…"];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    [content addSubview:self.targetMenu];
    self.connectButton = [self accentButton:@"Connecter" frame:NSMakeRect(334, 243, 122, 32) action:@selector(connectSelectedPeer:) color:[NSColor colorWithRed:0.12 green:0.42 blue:0.82 alpha:1.0]];
    [content addSubview:self.connectButton];

    [content addSubview:[self label:@"PORT RTP À TESTER" frame:NSMakeRect(24, 218, 190, 20) size:10 bold:YES]];
    self.endpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 184, 300, 30) pullsDown:NO];
    self.endpointMenu.target = self;
    self.endpointMenu.action = @selector(endpointChanged:);
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];
    [content addSubview:self.endpointMenu];
    [content addSubview:[self label:@"PGM" frame:NSMakeRect(338, 218, 50, 20) size:10 bold:YES]];
    self.programField = [[NSTextField alloc] initWithFrame:NSMakeRect(334, 184, 60, 30)];
    self.programField.stringValue = @"42";
    self.programField.alignment = NSTextAlignmentCenter;
    self.programField.font = [NSFont boldSystemFontOfSize:14.0];
    self.programField.textColor = [NSColor colorWithRed:0.55 green:0.90 blue:0.68 alpha:1.0];
    self.programField.backgroundColor = [NSColor colorWithRed:0.055 green:0.070 blue:0.095 alpha:1.0];
    [content addSubview:self.programField];
    self.testButton = [self accentButton:@"Tester" frame:NSMakeRect(402, 183, 54, 32) action:@selector(runTest:) color:[NSColor colorWithRed:0.08 green:0.58 blue:0.32 alpha:1.0]];
    [content addSubview:self.testButton];

    self.sessionInfo = [self label:@"" frame:NSMakeRect(24, 137, 432, 38) size:11 bold:NO];
    self.sessionInfo.maximumNumberOfLines = 2;
    self.lastTest = [self label:@"Aucun aller-retour validé" frame:NSMakeRect(24, 97, 432, 30) size:12 bold:YES];
    [content addSubview:self.sessionInfo];
    [content addSubview:self.lastTest];

    [content addSubview:[self accentButton:@"Réglages MIDI" frame:NSMakeRect(24, 35, 124, 36) action:@selector(openMidiSetup:) color:[NSColor colorWithRed:0.16 green:0.25 blue:0.39 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Actualiser" frame:NSMakeRect(158, 35, 100, 36) action:@selector(refreshNow:) color:[NSColor colorWithRed:0.20 green:0.25 blue:0.33 alpha:1.0]]];
    [content addSubview:[self accentButton:@"Simulateur Yamaha" frame:NSMakeRect(268, 35, 188, 36) action:@selector(startSimulator:) color:[NSColor colorWithRed:0.68 green:0.35 blue:0.08 alpha:1.0]]];

    NSTextField *footer = [self label:@"CL AUDIO · MIDI NETWORK · 2026" frame:NSMakeRect(24, 8, 432, 18) size:9 bold:YES];
    footer.alignment = NSTextAlignmentCenter;
    footer.textColor = [NSColor colorWithWhite:0.38 alpha:1.0];
    [content addSubview:footer];

    [self refreshEndpoints];
    self.discoveredPeers = [NSMutableOrderedSet orderedSet];
    self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
    self.serviceBrowser.delegate = self;
    [self.serviceBrowser searchForServicesOfType:@"_apple-midi._udp." inDomain:@"local."];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(refreshTimer:) userInfo:nil repeats:YES];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)setLamp:(NSColor *)color title:(NSString *)title detail:(NSString *)detail {
    self.lamp.layer.backgroundColor = color.CGColor;
    self.lamp.layer.shadowColor = color.CGColor;
    self.lamp.layer.shadowOpacity = 0.75;
    self.lamp.layer.shadowRadius = 8;
    self.headline.stringValue = title;
    self.detail.stringValue = detail;
}

- (void)refreshTimer:(NSTimer *)timer { (void)timer; [self refreshEndpoints]; }
- (void)refreshNow:(id)sender { (void)sender; [self refreshEndpoints]; [self inspectMidiDirectory]; }
- (void)endpointChanged:(id)sender { (void)sender; self.validatedEndpoint = nil; [self refreshEndpoints]; }
- (void)targetChanged:(id)sender {
    (void)sender;
    NSString *target = self.targetMenu.selectedItem.title;
    if (target.length && ![target hasPrefix:@"Recherche"] && ![target hasPrefix:@"Aucun"]) {
        [[NSUserDefaults standardUserDefaults] setObject:target forKey:@"preferredRtpPeer"];
    }
}

- (void)refreshTargetMenu {
    NSString *selected = [[NSUserDefaults standardUserDefaults] stringForKey:@"preferredRtpPeer"];
    NSMutableArray<NSString *> *available = [self.discoveredPeers.array mutableCopy];
    if (self.localNetworkName.length) [available removeObject:self.localNetworkName];
    if (selected.length && ![available containsObject:selected]) [available addObject:selected];
    NSArray<NSString *> *names = [available sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [self.targetMenu removeAllItems];
    [self.targetMenu addItemsWithTitles:names.count ? names : @[@"Aucun correspondant découvert"]];
    if (selected.length && [names containsObject:selected]) [self.targetMenu selectItemWithTitle:selected];
    [self stylePopup:self.targetMenu accent:[NSColor colorWithRed:0.34 green:0.72 blue:1.0 alpha:1.0]];
    self.connectButton.enabled = names.count > 0;
}

- (void)inspectMidiDirectory {
    if (self.peerInspectionRunning) return;
    self.peerInspectionRunning = YES;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[[self toolPath:@"list_rtp_peers.applescript"]];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.peerInspectionRunning = NO;
            if (finished.terminationStatus != 0) return;
            for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if ([line hasPrefix:@"SELF\t"]) self.localNetworkName = [line substringFromIndex:5];
                if ([line hasPrefix:@"PEER\t"]) [self.discoveredPeers addObject:[line substringFromIndex:5]];
            }
            [self refreshTargetMenu];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) self.peerInspectionRunning = NO;
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length) [self.discoveredPeers addObject:service.name];
    if (!moreComing) [self refreshTargetMenu];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)moreComing {
    (void)browser;
    if (service.name.length) [self.discoveredPeers removeObject:service.name];
    if (!moreComing) [self refreshTargetMenu];
}

- (void)connectSelectedPeer:(id)sender {
    (void)sender;
    NSString *peer = self.targetMenu.selectedItem.title ?: @"";
    if (!peer.length || [peer hasPrefix:@"Aucun"] || [peer hasPrefix:@"Recherche"]) return;
    [[NSUserDefaults standardUserDefaults] setObject:peer forKey:@"preferredRtpPeer"];
    self.connectButton.enabled = NO;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion RTP vers %@…", peer];
    NSString *helper = [NSString stringWithContentsOfFile:[self toolPath:@"connect_rtp_peer.applescript"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSString *escapedPeer = [[peer stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
                              stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *source = [helper stringByReplacingOccurrencesOfString:@"__CL_PEER__" withString:escapedPeer];
    NSDictionary *scriptError = nil;
    NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&scriptError];
    NSString *output = result.stringValue ?: @"";
    self.connectButton.enabled = YES;
    if (scriptError == nil && [output rangeOfString:@"already-connected:"].location != NSNotFound) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"%@ est déjà connecté · test MIDI requis", peer];
    } else if (scriptError == nil && [output rangeOfString:@"connected:"].location != NSNotFound) {
        self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion RTP établie avec %@ · test MIDI requis", peer];
    } else {
        NSString *reason = scriptError[NSAppleScriptErrorMessage] ?: @"erreur inconnue";
        self.lastTest.stringValue = [NSString stringWithFormat:@"Connexion impossible : %@", reason];
    }
}

- (void)refreshEndpoints {
    NSArray<NSString *> *sources = EndpointNames(YES);
    NSArray<NSString *> *destinations = EndpointNames(NO);
    NSString *selected = self.endpointMenu.selectedItem.title;
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    for (NSString *name in sources) {
        if ([name rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound) [candidates addObject:name];
    }
    for (NSString *name in destinations) {
        if ([name rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [name rangeOfString:@"session" options:NSCaseInsensitiveSearch].location != NSNotFound) [candidates addObject:name];
    }
    [self.endpointMenu removeAllItems];
    [self.endpointMenu addItemsWithTitles:candidates.array.count ? candidates.array : @[@"Aucun port RTP détecté"]];
    if (selected.length && [candidates containsObject:selected]) [self.endpointMenu selectItemWithTitle:selected];
    [self stylePopup:self.endpointMenu accent:[NSColor colorWithRed:0.67 green:0.53 blue:1.0 alpha:1.0]];

    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    BOOL hasSource = [sources containsObject:endpoint];
    BOOL hasDestination = [destinations containsObject:endpoint];
    MIDINetworkSession *session = [MIDINetworkSession defaultSession];
    self.sessionInfo.stringValue = [NSString stringWithFormat:@"Session API : %@ · port %lu · connexions déclarées : %lu\nEntrée : %@ · sortie : %@",
        session.isEnabled ? @"active" : @"indisponible", (unsigned long)session.networkPort,
        (unsigned long)session.connections.count, hasSource ? @"visible" : @"absente", hasDestination ? @"visible" : @"absente"];

    if (self.validatedEndpoint && [self.validatedEndpoint isEqualToString:endpoint]) {
        NSTimeInterval age = -[self.validatedAt timeIntervalSinceNow];
        [self setLamp:[NSColor systemGreenColor] title:@"RTP VALIDÉ" detail:[NSString stringWithFormat:@"Aller-retour confirmé il y a %.0f s sur %@", age, endpoint]];
    } else if (hasSource && hasDestination) {
        [self setLamp:[NSColor systemOrangeColor] title:@"RTP DISPONIBLE" detail:@"Le port est visible ; lancez un test pour valider le retour réel."];
    } else {
        [self setLamp:[NSColor systemRedColor] title:@"RTP HORS LIGNE" detail:@"Aucune paire entrée/sortie RTP exploitable n’est visible."];
    }
}

- (NSString *)toolPath:(NSString *)name {
    return [[NSBundle mainBundle].resourcePath stringByAppendingPathComponent:[@"Network Tools" stringByAppendingPathComponent:name]];
}

- (void)runTest:(id)sender {
    (void)sender;
    NSString *endpoint = self.endpointMenu.selectedItem.title ?: @"";
    NSInteger program = self.programField.integerValue;
    if ([endpoint hasPrefix:@"Aucun"] || program < 1 || program > 128) {
        self.lastTest.stringValue = @"Sélection ou Program Change invalide";
        return;
    }
    self.testButton.enabled = NO;
    self.lastTest.stringValue = [NSString stringWithFormat:@"Test en cours : %@ · PGM %ld…", endpoint, (long)program];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:[self toolPath:@"CLMIDIRoundTripTester"]];
    task.arguments = @[@"--endpoint", endpoint, @"--program", [NSString stringWithFormat:@"%ld", (long)program], @"--timeout", @"5"];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    task.terminationHandler = ^(NSTask *finished) {
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.testButton.enabled = YES;
            if (finished.terminationStatus == 0) {
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"latency_ms=([0-9.]+)" options:0 error:nil];
                NSTextCheckingResult *match = [regex firstMatchInString:output options:0 range:NSMakeRange(0, output.length)];
                NSString *latency = match ? [output substringWithRange:[match rangeAtIndex:1]] : @"?";
                self.validatedEndpoint = endpoint;
                self.validatedAt = [NSDate date];
                self.lastTest.stringValue = [NSString stringWithFormat:@"✓ PGM %ld confirmé · %@ ms", (long)program, latency];
            } else {
                self.validatedEndpoint = nil;
                NSString *reason = [output rangeOfString:@"TIMEOUT"].location != NSNotFound ? @"aucun retour reçu" : @"test impossible";
                self.lastTest.stringValue = [NSString stringWithFormat:@"Échec : %@", reason];
            }
            [self refreshEndpoints];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        self.testButton.enabled = YES;
        self.lastTest.stringValue = [NSString stringWithFormat:@"Impossible de lancer le test : %@", error.localizedDescription];
    }
}

- (void)openMidiSetup:(id)sender {
    (void)sender;
    NSString *source = [NSString stringWithContentsOfFile:[self toolPath:@"open_rtp_settings.applescript"]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (error) self.lastTest.stringValue = @"Impossible d’ouvrir directement les réglages RTP. Vérifiez l’autorisation Accessibilité.";
    else [self inspectMidiDirectory];
}

- (void)startSimulator:(id)sender {
    (void)sender;
    NSString *tool = [self toolPath:@"CLYamahaConsoleSimulator"];
    NSString *command = [NSString stringWithFormat:@"%@ --label Yamaha --delay-ms 80", [tool stringByReplacingOccurrencesOfString:@" " withString:@"\\ "]];
    NSString *script = [NSString stringWithFormat:@"tell application \"Terminal\" to do script \"%@\"", command];
    NSDictionary *error = nil;
    [[[NSAppleScript alloc] initWithSource:script] executeAndReturnError:&error];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        CLNetworkDelegate *delegate = [[CLNetworkDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
