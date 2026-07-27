#import <Cocoa/Cocoa.h>

@interface CLSuiteAppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSMutableDictionary<NSString *, NSButton *> *checks;
@property NSMutableDictionary<NSString *, NSView *> *cards;
@property NSSegmentedControl *liveSelector;
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
    box.borderColor = [NSColor colorWithCalibratedWhite:0.28 alpha:1];
    box.fillColor = [NSColor colorWithCalibratedWhite:0.105 alpha:1];

    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
    icon.imageScaling = NSImageScaleProportionallyUpOrDown;
    icon.image = [[NSImage alloc] initWithContentsOfURL:[self.resources URLByAppendingPathComponent:iconName]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *check = [NSButton checkboxWithTitle:title target:nil action:nil];
    check.state = NSControlStateValueOn;
    check.font = [NSFont systemFontOfSize:17 weight:NSFontWeightSemibold];
    check.contentTintColor = NSColor.whiteColor;
    self.checks[identifier] = check;

    NSTextField *detail = [self label:subtitle size:13 weight:NSFontWeightRegular color:[NSColor colorWithCalibratedWhite:0.70 alpha:1]];
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
        [box.heightAnchor constraintEqualToConstant:82]
    ]];
    self.cards[identifier] = box;
    return box;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    CGFloat height = self.uninstaller ? 710 : 690;
    NSRect frame = NSMakeRect(0, 0, 760, height);
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = self.uninstaller ? @"Désinstaller la Suite CL" : @"Installer la Suite CL";
    self.window.minSize = frame.size;
    [self.window center];

    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:frame];
    background.material = NSVisualEffectMaterialHUDWindow;
    background.state = NSVisualEffectStateActive;
    self.window.contentView = background;

    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.image = [[NSImage alloc] initWithContentsOfURL:[self.resources URLByAppendingPathComponent:@"CL_AUDIO.icns"]];
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    logo.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title = [self label:(self.uninstaller ? @"Désinstaller la Suite CL" : @"Installer la Suite CL")
                                size:27 weight:NSFontWeightBold color:NSColor.whiteColor];
    NSString *introText = self.uninstaller
        ? @"Choisissez uniquement les éléments à retirer. Ils resteront récupérables dans la Corbeille."
        : @"Choisissez votre version d’Ableton Live et les applications à installer.";
    NSTextField *intro = [self label:introText size:14 weight:NSFontWeightRegular color:[NSColor colorWithCalibratedWhite:0.72 alpha:1]];
    NSStackView *titles = [NSStackView stackViewWithViews:@[title, intro]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.alignment = NSLayoutAttributeLeading;
    titles.spacing = 4;
    NSStackView *header = [NSStackView stackViewWithViews:@[logo, titles]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 18;
    [NSLayoutConstraint activateConstraints:@[
        [logo.widthAnchor constraintEqualToConstant:72],
        [logo.heightAnchor constraintEqualToConstant:72]
    ]];

    NSMutableArray<NSView *> *mainViews = [NSMutableArray arrayWithObject:header];
    if (!self.uninstaller) {
        self.liveSelector = [NSSegmentedControl segmentedControlWithLabels:@[@"Ableton Live 12", @"Ableton Live 10"]
                                                               trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                     target:self
                                                                     action:@selector(liveChanged:)];
        self.liveSelector.selectedSegment = 0;
        self.liveSelector.segmentStyle = NSSegmentStyleRounded;
        [self.liveSelector.heightAnchor constraintEqualToConstant:34].active = YES;
        [mainViews addObject:self.liveSelector];
    }

    NSStackView *componentStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    componentStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    componentStack.spacing = 8;
    NSArray<NSArray<NSString *> *> *components = self.uninstaller ? @[
        @[@"autoscene", @"Paradis Latin AutoScene — Live 11/12", @"Périphérique Max for Live AutoScene.", @"ParadisLatin.jpg"],
        @[@"autoscene-live10", @"Paradis Latin AutoScene — Live 10", @"Variante dédiée à Ableton Live 10.", @"ParadisLatin.jpg"],
        @[@"remote", @"CL Audio Controller", @"Application, AbletonOSC, télécommande, LTC et X-Fader.", @"Controller.png"],
        @[@"builder", @"CL Arrangement Builder Live", @"Application Builder et Remote Script Ableton.", @"Builder.png"],
        @[@"midi-console", @"CL MIDI Console Monitor", @"Moniteur Max for Live et outils réseau MIDI.", @"MIDIConsole.png"]
    ] : @[
        @[@"autoscene", @"Paradis Latin AutoScene", @"Périphérique Max for Live pour Ableton Live 11 et 12.", @"ParadisLatin.jpg"],
        @[@"remote", @"CL Audio Controller", @"Application, AbletonOSC, télécommande, LTC et X-Fader.", @"Controller.png"],
        @[@"builder", @"CL Arrangement Builder Live", @"Application Builder et Remote Script Ableton.", @"Builder.png"],
        @[@"midi-console", @"CL MIDI Console Monitor", @"Moniteur Max for Live et outils réseau MIDI.", @"MIDIConsole.png"]
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

    NSButton *cancel = [NSButton buttonWithTitle:@"Annuler" target:self action:@selector(cancelPressed:)];
    cancel.bezelStyle = NSBezelStyleRounded;
    self.actionButton = [NSButton buttonWithTitle:(self.uninstaller ? @"Désinstaller" : @"Installer") target:self action:@selector(actionPressed:)];
    self.actionButton.bezelStyle = NSBezelStyleRounded;
    self.actionButton.keyEquivalent = @"\r";
    self.actionButton.contentTintColor = self.uninstaller ? NSColor.systemRedColor : NSColor.systemBlueColor;
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[status, spacer, cancel, self.actionButton]];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 10;
    [mainViews addObject:buttons];

    NSStackView *root = [NSStackView stackViewWithViews:mainViews];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 14;
    root.edgeInsets = NSEdgeInsetsMake(24, 28, 24, 28);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [background addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:background.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:background.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:background.topAnchor],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:background.bottomAnchor],
        [componentStack.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-56],
        [buttons.widthAnchor constraintEqualToAnchor:componentStack.widthAnchor]
    ]];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)liveChanged:(id)sender {
    BOOL live10 = self.liveSelector.selectedSegment == 1;
    [self.checks enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSButton *check, BOOL *stop) {
        BOOL enabled = !live10 || [key isEqualToString:@"autoscene"];
        check.enabled = enabled;
        check.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
        self.cards[key].alphaValue = enabled ? 1 : 0.38;
    }];
    self.checks[@"autoscene"].title = live10 ? @"Paradis Latin AutoScene — Live 10" : @"Paradis Latin AutoScene";
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
        environment[@"CL_SUITE_COMPONENTS"] = live10 ? @"autoscene-live10" : [selected componentsJoinedByString:@","];
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
                [selfRef showAlert:(selfRef.uninstaller ? @"Désinstallation terminée" : @"Installation terminée")
                              message:(selfRef.uninstaller ? @"Les éléments retirés restent récupérables dans la Corbeille." : @"Fermez complètement Ableton Live si celui-ci était ouvert, puis relancez-le.")
                                style:NSAlertStyleInformational];
            } else {
                selfRef.statusLabel.stringValue = @"Échec — consultez le rapport";
                [selfRef showAlert:@"L’opération a échoué" message:[@"Rapport : " stringByAppendingString:log] style:NSAlertStyleCritical];
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
