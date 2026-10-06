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

@interface CLInstallerDocumentView : NSView
@end
@implementation CLInstallerDocumentView
- (BOOL)isFlipped { return YES; }
@end

@interface CLSuiteAppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSMutableDictionary<NSString *, NSButton *> *checks;
@property NSMutableDictionary<NSString *, NSView *> *cards;
@property NSMutableDictionary<NSString *, NSStackView *> *componentGroups;
@property NSTextField *roleHelp;
@property NSSegmentedControl *liveSelector;
@property NSSegmentedControl *roleSelector;
@property NSView *liveSection;
@property NSScrollView *componentScroll;
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
        _componentGroups = [NSMutableDictionary dictionary];
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

    NSButton *check = [NSButton checkboxWithTitle:title target:self action:@selector(componentChanged:)];
    check.state = NSControlStateValueOn;
    check.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    check.contentTintColor = NSColor.whiteColor;
    self.checks[identifier] = check;

    NSTextField *detail = [self label:subtitle size:11 weight:NSFontWeightRegular color:[NSColor colorWithCalibratedWhite:0.76 alpha:1]];
    NSStackView *labels = [NSStackView stackViewWithViews:@[check, detail]];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 4;

    NSStackView *row = [NSStackView stackViewWithViews:@[icon, labels]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 8;
    row.edgeInsets = NSEdgeInsetsMake(6, 8, 6, 8);
    row.translatesAutoresizingMaskIntoConstraints = NO;
    box.contentView = row;
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:30],
        [icon.heightAnchor constraintEqualToConstant:30],
        [box.heightAnchor constraintEqualToConstant:48]
    ]];
    self.cards[identifier] = box;
    return box;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    CLInstallApplicationMenu();
    NSRect visibleFrame = NSScreen.mainScreen.visibleFrame;
    CGFloat width = MIN(960.0, visibleFrame.size.width - 60.0);
    CGFloat height = MIN(820.0, visibleFrame.size.height - 60.0);
    NSRect frame = NSMakeRect(0, 0, width, height);

    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = self.uninstaller ? @"Désinstaller la Suite CL" : @"Installer la Suite CL";
    self.window.minSize = NSMakeSize(860.0, 600.0);
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
        : @"Choisissez un usage pour voir ses applications, ou Personnalisé pour les sélectionner vous-même.";
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
    {
        NSTextField *roleTitle = [self label:@"1. Choisissez l’usage de ce Mac" size:14 weight:NSFontWeightSemibold color:NSColor.whiteColor];
        [mainViews addObject:roleTitle];
        self.roleSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Serveur", @"Ableton", @"MTC / Logic", @"Contrôle", @"Backup", @"Diagnostic", @"Personnalisé"]
                                                               trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                     target:self
                                                                     action:@selector(roleChanged:)];
        self.roleSelector.selectedSegment = 0;
        self.roleSelector.segmentStyle = NSSegmentStyleRounded;
        [self.roleSelector.heightAnchor constraintEqualToConstant:36].active = YES;
        [mainViews addObject:self.roleSelector];
    }

    NSTextField *componentsTitle = [self label:(self.uninstaller ? @"Éléments à retirer" : @"2. Applications et outils") size:14 weight:NSFontWeightSemibold color:NSColor.whiteColor];
    [mainViews addObject:componentsTitle];
    self.roleHelp = [self label:@"" size:13 weight:NSFontWeightRegular color:NSColor.lightGrayColor];
    [mainViews addObject:self.roleHelp];

    NSStackView *componentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    componentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    componentStack.spacing = 8;
    NSArray<NSArray<NSString *> *> *components = @[
        @[@"show_control", @"CL Show Control — moteur", @"Démarre le serveur local et le panneau de contrôle.", @"Controller.png"],
        @[@"showcue", @"CL ShowCue — conduite", @"Affiche les cues du show. Moteur local requis.", @"ShowCue.png"],
        @[@"cue_editor", @"CL Cue Editor — édition", @"Prépare les cues et sauvegarde les shows. Moteur local requis.", @"CueEditor.png"],
        @[@"control_client", @"Accès à un serveur distant", @"Ouvre le serveur HTTPS dans votre navigateur.", @"ShowCue.png"],
        @[@"ableton_osc", @"AbletonOSC", @"Extension Live 11/12 pour les commandes OSC.", @"Controller.png"],
        @[@"live_devices", @"Devices Live LTC / X-Fader", @"Devices de timecode et de fondu pour Ableton.", @"Controller.png"],
        @[@"absolute_mtc", @"CL Absolute MTC", @"Device Live de synchronisation temporelle.", @"MIDIConsole.png"],
        @[@"mtc_bridge", @"MTC Bridge", @"Application de synchro ouverte explicitement.", @"MIDIConsole.png"],
        @[@"sync_meter", @"Sync Meter", @"Diagnostic de synchro MTC.", @"Diagnostic.png"],
        @[@"show_backup", @"CL Show Backup — externe", @"Intégration externe à valider avant installation.", @"Controller.png"],
        @[@"network_manager", @"Network Manager", @"Vérifie les connexions MIDI et réseau.", @"MIDIConsole.png"],
        @[@"network_tools", @"Helpers et simulateurs", @"Tests et simulation des connexions MIDI.", @"MIDIConsole.png"],
        @[@"analyzer", @"MIDI Analyzer", @"Analyse ponctuelle.", @"Diagnostic.png"],
        @[@"performance_monitor", @"Performance Monitor", @"Mesures ponctuelles.", @"Diagnostic.png"],
        @[@"rtp_diagnostic", @"MIDI & RTP Diagnostic", @"Diagnostic ponctuel.", @"Diagnostic.png"],
        @[@"rtp_agent", @"Option agent RTP", @"Connexion MIDI réseau automatique en arrière-plan.", @"MIDIConsole.png"]
    ];
    NSArray *groups = @[
        @[@"Show et conduite", @[@"show_control", @"showcue", @"cue_editor", @"control_client"]],
        @[@"Ableton et synchronisation", @[@"ableton_osc", @"live_devices", @"absolute_mtc", @"mtc_bridge", @"sync_meter", @"show_backup"]],
        @[@"MIDI et réseau", @[@"network_manager", @"network_tools", @"analyzer", @"performance_monitor", @"rtp_diagnostic", @"rtp_agent"]]
    ];
    for (NSArray *group in groups) {
        NSStackView *section = [[NSStackView alloc] initWithFrame:NSZeroRect];
        section.orientation = NSUserInterfaceLayoutOrientationVertical;
        section.alignment = NSLayoutAttributeLeading;
        section.spacing = 4;
        [section addArrangedSubview:[self label:group[0] size:12 weight:NSFontWeightSemibold color:NSColor.lightGrayColor]];
        self.componentGroups[group[0]] = section;
        NSArray *ids = group[1];
        for (NSUInteger index = 0; index < ids.count; index += 2) {
            NSStackView *pair = [[NSStackView alloc] initWithFrame:NSZeroRect];
            pair.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            pair.distribution = NSStackViewDistributionFillEqually;
            pair.spacing = 8;
            for (NSUInteger column = index; column < MIN(index + 2, ids.count); column++) {
                for (NSArray<NSString *> *item in components) {
                    if ([item[0] isEqualToString:ids[column]]) {
                        [pair addArrangedSubview:[self componentCard:item[0] title:item[1] subtitle:item[2] iconName:item[3]]];
                    }
                }
            }
            [section addArrangedSubview:pair];
            [pair.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
        }
        [componentStack addArrangedSubview:section];
        [section.widthAnchor constraintEqualToAnchor:componentStack.widthAnchor].active = YES;
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
        if (view == componentStack) {
            [scrollContent addArrangedSubview:view];
        }
    }

    NSView *documentView = [[CLInstallerDocumentView alloc] initWithFrame:NSZeroRect];
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
    self.componentScroll = scrollView;

    NSMutableArray *fixedViews = [NSMutableArray array];
    for (NSView *view in mainViews) [fixedViews addObject:view == componentStack ? scrollView : view];
    root = [NSStackView stackViewWithViews:fixedViews];
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

        [header.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor],
        [componentStack.widthAnchor constraintEqualToAnchor:scrollContent.widthAnchor]
    ]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self roleChanged:self.roleSelector];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)roleChanged:(id)sender {
    (void)sender;
    NSInteger role = self.roleSelector.selectedSegment;
    NSArray *roles = @[@[@"show_control", @"showcue", @"cue_editor", @"network_manager", @"network_tools"],
        @[@"ableton_osc", @"live_devices", @"absolute_mtc"], @[@"mtc_bridge", @"sync_meter"],
        @[@"control_client"], @[@"show_backup", @"ableton_osc"],
        @[@"network_manager", @"network_tools", @"analyzer", @"performance_monitor", @"rtp_diagnostic"], @[]];
    [self.checks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *check, BOOL *stop) {
        BOOL selected = role < 6 && [roles[role] containsObject:key];
        check.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        check.enabled = role == 6 || (role == 1 && ([key isEqualToString:@"rtp_agent"] || [key isEqualToString:@"mtc_bridge"]));
        self.cards[key].hidden = !(selected || check.enabled);
    }];
    for (NSStackView *section in self.componentGroups.allValues) {
        BOOL visible = NO;
        for (NSView *view in section.arrangedSubviews) {
            if (![view isKindOfClass:NSStackView.class]) continue;
            NSStackView *pair = (NSStackView *)view;
            BOOL pairVisible = NO;
            for (NSView *card in pair.arrangedSubviews) if (!card.hidden) pairVisible = YES;
            pair.hidden = !pairVisible;
            visible |= pairVisible;
        }
        section.hidden = !visible;
    }
    NSArray *descriptions = @[
        @"Sur ce Mac : moteur CL, conduite ShowCue, éditeur de cues et outils réseau.",
        @"Sur le Mac qui lit Ableton : extensions Live. MTC Bridge et agent RTP sont optionnels.",
        @"Pour recevoir et vérifier le timecode dans Logic ou un autre lecteur MTC.",
        @"Pour accéder à un autre Mac : adresse HTTPS du serveur demandée à l’installation.",
        @"Pour le poste de secours : intégration CL Show Backup externe requise.",
        @"Pour vérifier les connexions et mesurer les performances MIDI.",
        @"Cochez les applications souhaitées. ShowCue et Cue Editor utilisent le moteur local."
    ];
    self.roleHelp.stringValue = descriptions[role];
    self.liveSelector.enabled = role == 1 || role == 4 || role == 6;
    self.liveSection.hidden = !self.liveSelector.enabled;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.window.contentView layoutSubtreeIfNeeded];
        NSClipView *clip = self.componentScroll.contentView;
        [clip scrollToPoint:NSZeroPoint];
        [self.componentScroll reflectScrolledClipView:clip];
    });

}

- (void)componentChanged:(id)sender {
    if (self.roleSelector.selectedSegment == 6 && !self.uninstaller &&
        (self.checks[@"showcue"].state == NSControlStateValueOn || self.checks[@"cue_editor"].state == NSControlStateValueOn)) {
        self.checks[@"show_control"].state = NSControlStateValueOn;
    }
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
    NSArray *roleNames = @[@"show_server", @"ableton_reader", @"mtc_logic", @"control_station", @"show_backup", @"diagnostics", @"custom"];
    NSInteger role = self.roleSelector.selectedSegment;
    environment[@"CL_SUITE_ROLE"] = roleNames[role];
    if (role == 6) environment[@"CL_SUITE_ROLE_COMPONENTS"] = [selected componentsJoinedByString:@","];
    if (role == 1) {
        NSMutableArray *features = [NSMutableArray array];
        if ([selected containsObject:@"rtp_agent"]) [features addObject:@"rtp"];
        if ([selected containsObject:@"mtc_bridge"]) [features addObject:@"mtc_bridge"];
        environment[@"CL_SUITE_ROLE_FEATURES"] = [features componentsJoinedByString:@","];
    }
    if (!self.uninstaller) {
        NSAlert *migration = [[NSAlert alloc] init];
        migration.messageText = @"Migration de l’installation existante";
        NSString *auditSummary = @"Audit indisponible : consulter le rapport avant remplacement.";
        @try {
            NSTask *auditTask = [[NSTask alloc] init];
            auditTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
            auditTask.arguments = @[@"python3", [[self.resources URLByAppendingPathComponent:@"role_install.py"] path], @"audit", roleNames[role]];
            auditTask.environment = environment;
            NSPipe *pipe = [NSPipe pipe]; auditTask.standardOutput = pipe; auditTask.standardError = pipe;
            [auditTask launch];
            NSData *auditData = [pipe.fileHandleForReading readDataToEndOfFile]; [auditTask waitUntilExit];
            NSArray *entries = [NSJSONSerialization JSONObjectWithData:auditData options:0 error:nil];
            if ([entries isKindOfClass:NSArray.class]) {
                NSMutableArray *lines = [NSMutableArray array];
                for (NSDictionary *entry in entries) {
                    [lines addObject:[NSString stringWithFormat:@"• %@ : %@", entry[@"kind"], [entry[@"path"] lastPathComponent]]];
                }
                auditSummary = lines.count ? [lines componentsJoinedByString:@"\n"] : @"Aucun ancien composant détecté.";
            }
        } @catch (NSException *exception) { (void)exception; }

        migration.informativeText = @"Le moteur audite les apps, anciens agents, sauvegardes et configurations. Migrer ou supprimer les anciens composants les déplace dans la Corbeille et retire leurs services. Conserver laisse les éléments en place et signale les écarts. Les configurations utilisateur sont toujours conservées.";
        migration.informativeText = [NSString stringWithFormat:@"%@\n\n%@", auditSummary, migration.informativeText];
        [migration addButtonWithTitle:@"Migrer"]; [migration addButtonWithTitle:@"Supprimer anciens composants"]; [migration addButtonWithTitle:@"Conserver"];
        NSInteger choice = [migration runModal] - NSAlertFirstButtonReturn;
        environment[@"CL_SUITE_MIGRATION"] = @[@"migrate", @"remove", @"keep"][MAX(0, MIN(2, choice))];
        if ([selected containsObject:@"control_client"]) {
            NSAlert *destination = [[NSAlert alloc] init]; destination.messageText = @"Serveur Show Control";
            destination.informativeText = @"Adresse HTTPS explicite du serveur. Cette adresse est conservée dans le client ; aucun service local n’est installé.";
            NSTextField *url = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 400, 28)]; url.placeholderString = @"https://serveur.local:8443"; destination.accessoryView = url;
            [destination addButtonWithTitle:@"Continuer"]; [destination runModal];
            environment[@"CL_SUITE_SERVER_URL"] = url.stringValue;
        }
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
                NSString *successMessage = selfRef.uninstaller
                    ? @"Les composants et services du rôle ont été retirés. Les configurations sont conservées et les anciens composants restent récupérables dans la Corbeille."
                    : @"Les composants du rôle choisi sont installés et vérifiés. Aucun service RTP n’est ajouté sans sélection explicite. Consultez le rapport puis effectuez la checklist du rôle ; relancez Ableton uniquement si des extensions Live ont été installées.";
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
