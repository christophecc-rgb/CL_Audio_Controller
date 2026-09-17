#import <Cocoa/Cocoa.h>

static void CLInstallApplicationMenu(void) {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *applicationItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@""];
    NSString *appName = NSProcessInfo.processInfo.processName;
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:[@"Quitter " stringByAppendingString:appName]
                                                     action:@selector(terminate:)
                                              keyEquivalent:@"q"];
    quitItem.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [applicationMenu addItem:quitItem];
    applicationItem.submenu = applicationMenu;
    [mainMenu addItem:applicationItem];
    NSApp.mainMenu = mainMenu;
}

@interface CLSuiteAppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSMutableDictionary<NSString *, NSButton *> *checks;
@property NSMutableDictionary<NSString *, NSView *> *cards;
@property NSSegmentedControl *liveSelector;
@property NSSegmentedControl *roleSelector;
@property NSView *liveSection;
@property NSButton *actionButton;
@property NSProgressIndicator *progress;
@property NSTextField *statusLabel;
@property BOOL uninstaller;
@property NSURL *resources;
@end

@implementation CLSuiteAppDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        _checks = [NSMutableDictionary dictionary];
        _cards = [NSMutableDictionary dictionary];
        _resources = NSBundle.mainBundle.resourceURL;
        _uninstaller = [NSBundle.mainBundle.bundleIdentifier containsString:@"uninstaller"];
    }
    return self;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.maximumNumberOfLines = 2;
    return label;
}

- (NSView *)componentCard:(NSString *)identifier
                    title:(NSString *)title
                 subtitle:(NSString *)subtitle
                 iconName:(NSString *)iconName {
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.boxType = NSBoxCustom;
    box.cornerRadius = 12;
    box.borderWidth = 1;
    box.borderColor = [NSColor colorWithCalibratedRed:0.20 green:0.24 blue:0.30 alpha:1];
    box.fillColor = [NSColor colorWithCalibratedRed:0.075 green:0.09 blue:0.12 alpha:1];

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.image = [[NSImage alloc] initWithContentsOfURL:[self.resources URLByAppendingPathComponent:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *check = [NSButton checkboxWithTitle:title target:nil action:nil];
    check.state = NSControlStateValueOn;
    check.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    check.contentTintColor = NSColor.whiteColor;
    self.checks[identifier] = check;

    NSTextField *detail = [self label:subtitle size:13 weight:NSFontWeightRegular color:[NSColor colorWithCalibratedWhite:0.76 alpha:1]];
    NSStackView *labels = [NSStackView stackViewWithViews:@[check, detail]];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 4;

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, labels]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 16;
    row.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    box.contentView = row;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:54],
        [icon.heightAnchor constraintEqualToConstant:54],
        [box.heightAnchor constraintEqualToConstant:78]
    ]];
    self.cards[identifier] = box;
    return box;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    CLInstallApplicationMenu();
    NSRect visibleFrame = NSScreen.mainScreen.visibleFrame;
    CGFloat width = MIN(780.0, visibleFrame.size.width - 60.0);
    CGFloat height = MIN(700.0, visibleFrame.size.height - 60.0);
    NSRect frame = NSMakeRect(0, 0, width, height);

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = self.uninstaller ? @"Désinstaller la Suite CL" : @"Installer la Suite CL";
    self.window.minSize = NSMakeSize(680.0, 520.0);
    [self.window center];

    NSView *background = [[NSView alloc] initWithFrame:frame];
    background.wantsLayer = YES;
    background.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.065 blue:0.085 alpha:1].CGColor;
    self.window.contentView = background;

    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.image = [[NSImage alloc] initWithContentsOfURL:[self.resources URLByAppendingPathComponent:@"CL_AUDIO.icns"]];
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    logo.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *paradisLogo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    paradisLogo.image = [[NSImage alloc] initWithContentsOfURL:[self.resources URLByAppendingPathComponent:@"ParadisLatin.jpg"]];
    paradisLogo.imageScaling = NSImageScaleProportionallyUpOrDown;
    paradisLogo.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [self label:(self.uninstaller ? @"Désinstaller la Suite CL" : @"Installer la Suite CL")
                                size:27 weight:NSFontWeightBold color:NSColor.whiteColor];
    NSString *introText = self.uninstaller
        ? @"Choisissez uniquement les éléments à retirer. Ils resteront récupérables dans la Corbeille."
        : @"Choisissez le rôle de ce Mac. Les anciennes versions remplacées seront déplacées dans la Corbeille et resteront récupérables.";
    NSTextField *intro = [self label:introText size:14 weight:NSFontWeightRegular color:[NSColor colorWithCalibratedWhite:0.72 alpha:1]];
    NSStackView *titles = [NSStackView stackViewWithViews:@[title, intro]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.alignment = NSLayoutAttributeLeading;
    titles.spacing = 4;
    NSView *headerSpacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [headerSpacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = [NSStackView stackViewWithViews:@[logo, titles, headerSpacer, paradisLogo]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 18;
    [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor constraintEqualToConstant:72],
        [logo.heightAnchor constraintEqualToConstant:72],
        [paradisLogo.widthAnchor constraintEqualToConstant:132],
        [paradisLogo.heightAnchor constraintEqualToConstant:58]
    ]];

    NSMutableArray<NSView *> *mainViews = [NSMutableArray arrayWithObject:header];
    if (!self.uninstaller) {
        NSTextField *roleTitle = [self label:@"1. Choisissez l’usage de ce Mac" size:14 weight:NSFontWeightSemibold color:NSColor.whiteColor];
        [mainViews addObject:roleTitle];
        self.roleSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Mac Télécommande", @"Mac Ableton Lecteur", @"Simulateur console", @"Personnalisé"]
                                                               trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                     target:self
                                                                     action:@selector(roleChanged:)];
        self.roleSelector.selectedSegment = 0;
        self.roleSelector.segmentStyle = NSSegmentStyleRounded;
        [self.roleSelector.heightAnchor constraintEqualToConstant:36].active = YES;
        [mainViews addObject:self.roleSelector];
        NSTextField *liveTitle = [self label:@"2. Choisissez la version d’Ableton Live" size:14 weight:NSFontWeightSemibold color:NSColor.whiteColor];
        self.liveSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Ableton Live 12", @"Ableton Live 10"]
                                                               trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                     target:self
                                                                     action:@selector(liveChanged:)];
        self.liveSelector.selectedSegment = 0;
        self.liveSelector.segmentStyle = NSSegmentStyleRounded;
        [self.liveSelector.heightAnchor constraintEqualToConstant:34].active = YES;
        NSStackView *liveSection = [NSStackView stackViewWithViews:@[liveTitle, self.liveSelector]];
        liveSection.orientation = NSUserInterfaceLayoutOrientationVertical;
        liveSection.alignment = NSLayoutAttributeLeading;
        liveSection.spacing = 7;
        self.liveSection = liveSection;
        [mainViews addObject:liveSection];
    }

    NSTextField *componentsTitle = [self label:(self.uninstaller ? @"Éléments à retirer" : @"Composants inclus") size:14 weight:NSFontWeightSemibold color:NSColor.whiteColor];
    [mainViews addObject:componentsTitle];

    NSStackView *componentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    componentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    componentStack.spacing = 8;
    NSArray<NSArray<NSString *> *> *components = self.uninstaller ? @[
        @[@"autoscene", @"Paradis Latin AutoScene — Live 11/12", @"Périphérique Max for Live AutoScene.", @"ParadisLatin.jpg"],
        @[@"autoscene-live10", @"Paradis Latin AutoScene — Live 10", @"Variante dédiée à Ableton Live 10.", @"ParadisLatin.jpg"],
        @[@"controller", @"Mac Télécommande — RTP émetteur-récepteur", @"Show Control, ShowCue et Cue Editor, ressources CL, découverte Bonjour et liaison RTP-MIDI bidirectionnelle avec retours consoles.", @"Controller.png"],
        @[@"ableton-reader", @"Mac Ableton Lecteur — RTP émetteur-récepteur", @"AbletonOSC, LTC, X-Fader et agent RTP-MIDI bidirectionnel à démarrage automatique.", @"Controller.png"],
        @[@"builder", @"CL Arrangement Builder", @"Application Builder et Remote Script Ableton.", @"Builder.png"],
        @[@"showcue", @"CL ShowCue + Cue Editor", @"Conduite du spectacle et éditeur, sessions transportables et bibliothèques CL5 / QL1.", @"ShowCue.png"],
        @[@"show-audio-builder", @"CL Audio Export", @"Export audio WAV/MP3 par scène et medleys.", @"AudioExport.png"],
        @[@"midi-console", @"CL MIDI Network Manager + simulateur", @"Diagnostic MIDI, retours consoles et simulateur intégré IAC/RTP.", @"MIDIConsole.png"],
        @[@"diagnostic-tools", @"Outils de diagnostic CL", @"MIDI & RTP Diagnostic, MIDI Analyzer et Performance Monitor.", @"Diagnostic.png"]
    ] : @[
        @[@"autoscene", @"Paradis Latin AutoScene", @"Périphérique Max for Live pour Ableton Live 11 et 12.", @"ParadisLatin.jpg"],
        @[@"controller", @"Mac Télécommande", @"Show Control, ShowCue et Cue Editor, ressources CL et serveur web.", @"Controller.png"],
        @[@"ableton-reader", @"Mac Ableton Lecteur", @"AbletonOSC, LTC, X-Fader et agent RTP léger.", @"Controller.png"],
        @[@"builder", @"CL Arrangement Builder", @"Application Builder et Remote Script Ableton.", @"Builder.png"],
        @[@"showcue", @"CL ShowCue + Cue Editor", @"Conduite du spectacle et éditeur, sessions transportables et bibliothèques CL5 / QL1.", @"ShowCue.png"],
        @[@"show-audio-builder", @"CL Audio Export", @"Export audio WAV/MP3 par scène et medleys.", @"AudioExport.png"],
        @[@"midi-console", @"CL MIDI Network Manager + simulateur", @"Diagnostic, retours consoles et tests IAC/RTP dans une seule application.", @"MIDIConsole.png"],
        @[@"diagnostic-tools", @"Outils de diagnostic CL", @"MIDI & RTP Diagnostic, MIDI Analyzer et Performance Monitor.", @"Diagnostic.png"]
    ];
    for (NSArray<NSString *> *item in components) {
        [componentStack addArrangedSubview:[self componentCard:item[0] title:item[1] subtitle:item[2] iconName:item[3]]];
    }
    [mainViews addObject:componentStack];

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.indeterminate = YES;
    self.progress.displayedWhenStopped = YES;
    self.progress.hidden = YES;
    [self.progress.widthAnchor constraintEqualToConstant:220].active = YES;
    [self.progress.heightAnchor constraintEqualToConstant:14].active = YES;
    self.statusLabel = [self label:(self.uninstaller ? @"Prêt à désinstaller" : @"Prêt à installer") size:13 weight:NSFontWeightSemibold color:[NSColor colorWithCalibratedWhite:0.78 alpha:1]];
    NSStackView *status = [NSStackView stackViewWithViews:@[self.progress, self.statusLabel]];
    status.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    status.spacing = 8;

    NSButton *quit = [NSButton buttonWithTitle:@"Quitter" target:self action:@selector(cancelPressed:)];
    quit.bezelStyle = NSBezelStyleRounded;
    quit.keyEquivalent = @"\033";
    self.actionButton = [NSButton buttonWithTitle:(self.uninstaller ? @"Désinstaller" : @"Installer") target:self action:@selector(actionPressed:)];
    self.actionButton.bezelStyle = NSBezelStyleRounded;
    self.actionButton.keyEquivalent = @"\r";
    self.actionButton.contentTintColor = self.uninstaller ? NSColor.systemRedColor : NSColor.systemBlueColor;
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[status, spacer, quit, self.actionButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 10;
    [mainViews addObject:buttons];

    NSStackView *root = nil;
    NSStackView *scrollContent = [[NSStackView alloc] initWithFrame:NSZeroRect];
    scrollContent.orientation = NSUserInterfaceLayoutOrientationVertical;
    scrollContent.alignment = NSLayoutAttributeLeading;
    scrollContent.spacing = 12;
    scrollContent.translatesAutoresizingMaskIntoConstraints = NO;

    for (NSView *view in mainViews) {
        if (view != buttons) {
            [scrollContent addArrangedSubview:view];
        }
    }

    NSView *documentView = [[NSView alloc] initWithFrame:NSZeroRect];
    documentView.translatesAutoresizingMaskIntoConstraints = NO;
    [documentView addSubview:scrollContent];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;
    scrollView.documentView = documentView;

    root = [NSStackView stackViewWithViews:@[scrollView, buttons]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(20, 30, 20, 30);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    [background addSubview:root];

    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:background.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:background.bottomAnchor],

        [scrollView.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-60],
        [buttons.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],

        [documentView.widthAnchor constraintEqualToAnchor:scrollView.contentView.widthAnchor],

        [scrollContent.leadingAnchor constraintEqualToAnchor:documentView.leadingAnchor],
        [scrollContent.trailingAnchor constraintEqualToAnchor:documentView.trailingAnchor],
        [scrollContent.topAnchor constraintEqualToAnchor:documentView.topAnchor],
        [scrollContent.bottomAnchor constraintEqualToAnchor:documentView.bottomAnchor],

        [header.widthAnchor constraintEqualToAnchor:scrollContent.widthAnchor],
        [componentStack.widthAnchor constraintEqualToAnchor:scrollContent.widthAnchor]
    ]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    if (!self.uninstaller) [self roleChanged:self.roleSelector];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)liveChanged:(id)sender {
    BOOL live10 = self.liveSelector.selectedSegment == 1;
    self.checks[@"autoscene"].title = live10 ? @"Paradis Latin AutoScene — Live 10" : @"Paradis Latin AutoScene";
}

- (void)roleChanged:(id)sender {
    (void)sender;
    NSInteger role = self.roleSelector.selectedSegment;
    if (role == 3) {
        [self.checks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *check, BOOL *stop) { check.enabled = YES; }];
        [self.cards enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSView *card, BOOL *stop) { card.alphaValue = 1.0; }];
        self.liveSelector.enabled = YES;
        self.liveSection.hidden = NO;
        return;
    }
    [self.checks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *check, BOOL *stop) {
        BOOL selected = (role == 0 && ([key isEqualToString:@"controller"] || [key isEqualToString:@"diagnostic-tools"])) ||
                        (role == 1 && ([key isEqualToString:@"ableton-reader"] || [key isEqualToString:@"builder"] || [key isEqualToString:@"autoscene"])) ||
                        (role == 2 && [key isEqualToString:@"midi-console"]);
        check.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        check.enabled = NO;
        self.cards[key].alphaValue = selected ? 1.0 : 0.28;
    }];
    self.liveSelector.enabled = role == 1;
    self.liveSection.hidden = role != 1;
}

- (void)cancelPressed:(id)sender { [NSApp terminate:nil]; }

- (void)showAlert:(NSString *)title message:(NSString *)message style:(NSAlertStyle)style {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = message;
    alert.alertStyle = style;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (NSString *)failureMessageForLog:(NSString *)log {
    NSString *contents = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:nil];
    __block NSString *reason = nil;
    [[contents componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]
        enumerateObjectsWithOptions:NSEnumerationReverse
                         usingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
        if ([line hasPrefix:@"ERREUR : "]) {
            reason = [line substringFromIndex:@"ERREUR : ".length];
            *stop = YES;
        }
    }];
    if (reason.length) {
        return [NSString stringWithFormat:@"%@\n\nRapport complet : %@", reason, log];
    }
    return [@"Consultez le rapport complet : " stringByAppendingString:log];
}

- (void)actionPressed:(id)sender {
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    for (NSString *key in self.checks) if (self.checks[key].state == NSControlStateValueOn) [selected addObject:key];
    [selected sortUsingSelector:@selector(compare:)];
    if (!selected.count) {
        [self showAlert:@"Aucun composant sélectionné" message:@"Sélectionnez au moins un élément." style:NSAlertStyleWarning];
        return;
    }
    NSAlert *confirmation = [[NSAlert alloc] init];
    confirmation.messageText = @"Confirmer l’opération";
    confirmation.informativeText = [NSString stringWithFormat:@"%lu composant(s) seront %@. Voulez-vous continuer ?", (unsigned long)selected.count, self.uninstaller ? @"retirés" : @"installés"];
    [confirmation addButtonWithTitle:self.uninstaller ? @"Désinstaller" : @"Installer"];
    [confirmation addButtonWithTitle:@"Annuler"];
    confirmation.alertStyle = self.uninstaller ? NSAlertStyleWarning : NSAlertStyleInformational;
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;
    [self runEngine:selected];
}

- (void)runEngine:(NSArray<NSString *> *)selected {
    self.actionButton.enabled = NO;
    self.progress.hidden = NO;
    self.progress.indeterminate = YES;
    [self.progress startAnimation:nil];
    self.statusLabel.stringValue = self.uninstaller ? @"Désinstallation en cours…" : @"Installation et vérification en cours…";
    NSString *engineName = self.uninstaller ? @"Desinstaller_La_Suite_CL.command" : @"Installer_Toute_La_Suite_CL.command";
    NSString *engine = [[self.resources URLByAppendingPathComponent:engineName] path];
    NSString *log = self.uninstaller ? @"/private/tmp/CL_Suite_Desinstallateur.log" : @"/private/tmp/CL_Suite_Installer.log";
    [[NSFileManager defaultManager] createFileAtPath:log contents:nil attributes:nil];
    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:log];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/bash"];
    task.arguments = @[engine];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"CL_SUITE_NONINTERACTIVE"] = @"1";
    if (self.uninstaller) {
        environment[@"CL_SUITE_UNINSTALL_COMPONENTS"] = [selected componentsJoinedByString:@","];
    } else {
        BOOL live10 = self.liveSelector.selectedSegment == 1;
        environment[@"CL_SUITE_LIVE_FAMILY"] = live10 ? @"10" : @"12";
        environment[@"CL_SUITE_COMPONENTS"] = [selected componentsJoinedByString:@","];
    }
    task.environment = environment;
    task.standardOutput = output;
    task.standardError = output;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        [output closeFile];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) selfRef = weakSelf;
            [selfRef.progress stopAnimation:nil];
            selfRef.progress.indeterminate = NO;
            selfRef.progress.minValue = 0;
            selfRef.progress.maxValue = 100;
            selfRef.progress.doubleValue = 100;
            selfRef.actionButton.enabled = YES;
            if (finished.terminationStatus == 0) {
                selfRef.statusLabel.stringValue = @"Opération terminée";
                BOOL installedController = !selfRef.uninstaller && [selected containsObject:@"controller"];
                BOOL installedAbletonReader = !selfRef.uninstaller && [selected containsObject:@"ableton-reader"];
                BOOL installedNetworkAssistant = !selfRef.uninstaller && [selected containsObject:@"midi-console"];
                NSString *successMessage = installedController
                    ? @"Le rôle Mac Télécommande est installé. Les versions remplacées sont dans la Corbeille. La liaison RTP-MIDI, la découverte Bonjour et les retours consoles démarrent automatiquement à l’ouverture de session."
                    : (installedAbletonReader
                       ? @"Le rôle Mac Ableton Lecteur est installé. Son agent RTP-MIDI émetteur-récepteur démarre automatiquement à l’ouverture de session. Fermez puis relancez Ableton Live s’il était ouvert."
                       : (installedNetworkAssistant
                          ? @"CL MIDI Network Manager et son simulateur IAC/RTP intégré ont été installés. Acceptez l’autorisation Accessibilité si macOS la demande."
                          : (selfRef.uninstaller ? @"Les éléments retirés restent récupérables dans la Corbeille." : @"Fermez complètement Ableton Live si celui-ci était ouvert, puis relancez-le.")));
                [selfRef showAlert:(selfRef.uninstaller ? @"Désinstallation terminée" : @"Installation terminée")
                              message:successMessage
                                style:NSAlertStyleInformational];
            } else {
                selfRef.statusLabel.stringValue = @"Échec — consultez le rapport";
                [selfRef showAlert:@"L’opération a échoué"
                              message:[selfRef failureMessageForLog:log]
                                style:NSAlertStyleCritical];
            }
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        [output closeFile];
        [self.progress stopAnimation:nil];
        self.actionButton.enabled = YES;
        [self showAlert:@"Impossible de démarrer" message:error.localizedDescription style:NSAlertStyleCritical];
    }
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        CLSuiteAppDelegate *delegate = [[CLSuiteAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
