#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>

static NSString *CLMidiEndpointName(MIDIEndpointRef endpoint) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) != noErr || value == NULL) {
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &value);
    }
    return CFBridgingRelease(value) ?: @"";
}

static NSArray<NSString *> *CLMidiEndpointNames(void) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (ItemCount index = 0; index < MIDIGetNumberOfSources(); index++) {
        NSString *name = CLMidiEndpointName(MIDIGetSource(index));
        if (name.length) [names addObject:name];
    }
    for (ItemCount index = 0; index < MIDIGetNumberOfDestinations(); index++) {
        NSString *name = CLMidiEndpointName(MIDIGetDestination(index));
        if (name.length) [names addObject:name];
    }
    return names.array;
}

@interface CLYamahaRow : NSObject
@property NSUInteger index;
@property NSButton *power;
@property NSTextField *nameField;
@property NSPopUpButton *endpointMenu;
@property NSPopUpButton *channelMenu;
@property NSTextField *delayField;
@property NSTextField *statusLabel;
@property NSTask *task;
@end
@implementation CLYamahaRow @end

@interface CLYamahaSimulatorDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSView *rowsView;
@property NSMutableArray<CLYamahaRow *> *rows;
@property NSArray<NSString *> *endpoints;
@property NSTextField *summary;
@property NSArray<NSDictionary *> *savedConfigs;
@end

@implementation CLYamahaSimulatorDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = text;
    field.editable = NO;
    field.bordered = NO;
    field.drawsBackground = NO;
    field.textColor = [NSColor colorWithWhite:0.78 alpha:1.0];
    field.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return field;
}

- (NSButton *)button:(NSString *)title frame:(NSRect)frame action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = self;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.rows = [NSMutableArray array];
    self.endpoints = CLMidiEndpointNames();
    self.savedConfigs = [NSUserDefaults.standardUserDefaults arrayForKey:@"CLYamahaSimulatorConsoles"] ?: @[];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 760, 500)
                                              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL Console Simulator";
    self.window.backgroundColor = [NSColor colorWithRed:0.035 green:0.045 blue:0.060 alpha:1.0];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSView *content = self.window.contentView;
    NSTextField *title = [self label:@"CL CONSOLE SIMULATOR" frame:NSMakeRect(24, 450, 470, 30) size:21 bold:YES];
    title.textColor = [NSColor colorWithRed:0.45 green:0.78 blue:1.0 alpha:1.0];
    [content addSubview:title];
    [content addSubview:[self label:@"Simulations indépendantes · Program Change aller-retour" frame:NSMakeRect(25, 429, 500, 20) size:11 bold:NO]];

    NSArray *headers = @[@"ACTIVE", @"CONSOLE", @"PORT MIDI / RTP", @"CANAL", @"DÉLAI", @"ÉTAT"];
    NSArray *xs = @[@24, @76, @204, @448, @532, @606];
    NSArray *widths = @[@48, @122, @238, @78, @68, @128];
    for (NSUInteger i = 0; i < headers.count; i++) {
        [content addSubview:[self label:headers[i] frame:NSMakeRect([xs[i] doubleValue], 397, [widths[i] doubleValue], 18) size:9 bold:YES]];
    }

    self.rowsView = [[NSView alloc] initWithFrame:NSMakeRect(16, 105, 728, 286)];
    [content addSubview:self.rowsView];
    NSUInteger initialCount = self.savedConfigs.count ? MIN(self.savedConfigs.count, 6) : 2;
    for (NSUInteger index = 0; index < initialCount; index++) [self addRowWithDefaults:index];

    [content addSubview:[self button:@"＋ Ajouter une console" frame:NSMakeRect(24, 58, 170, 34) action:@selector(addConsole:)]];
    [content addSubview:[self button:@"Tout démarrer" frame:NSMakeRect(204, 58, 130, 34) action:@selector(startAll:)]];
    [content addSubview:[self button:@"Tout arrêter" frame:NSMakeRect(344, 58, 130, 34) action:@selector(stopAll:)]];
    [content addSubview:[self button:@"Actualiser les ports" frame:NSMakeRect(484, 58, 160, 34) action:@selector(refreshPorts:)]];
    self.summary = [self label:@"2 consoles configurées · toutes arrêtées" frame:NSMakeRect(24, 25, 710, 20) size:11 bold:YES];
    [content addSubview:self.summary];
}

- (NSString *)defaultEndpointForIndex:(NSUInteger)index {
    NSArray *keywords = index == 0 ? @[@"CL5", @"Session RTP"] : @[@"QL1", @"Session RTP"];
    for (NSString *keyword in keywords) {
        for (NSString *endpoint in self.endpoints) {
            if ([endpoint rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) return endpoint;
        }
    }
    return self.endpoints.firstObject ?: @"Aucun port MIDI";
}

- (void)addRowWithDefaults:(NSUInteger)index {
    if (self.rows.count >= 6) return;
    CLYamahaRow *row = [[CLYamahaRow alloc] init];
    row.index = index;
    CGFloat y = 238 - (self.rows.count * 45);
    NSView *line = [[NSView alloc] initWithFrame:NSMakeRect(0, y, 728, 40)];
    line.wantsLayer = YES;
    line.layer.backgroundColor = [NSColor colorWithWhite:0.10 alpha:1.0].CGColor;
    line.layer.cornerRadius = 7.0;
    [self.rowsView addSubview:line];

    row.power = [[NSButton alloc] initWithFrame:NSMakeRect(10, 9, 26, 24)];
    row.power.buttonType = NSButtonTypeSwitch;
    row.power.target = self;
    row.power.action = @selector(toggleConsole:);
    row.power.tag = (NSInteger)index;
    [line addSubview:row.power];

    row.nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(55, 8, 120, 25)];
    row.nameField.stringValue = index == 0 ? @"CL5" : (index == 1 ? @"QL1" : [NSString stringWithFormat:@"Console %lu", (unsigned long)index + 1]);
    [line addSubview:row.nameField];

    row.endpointMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(183, 7, 236, 27) pullsDown:NO];
    [row.endpointMenu addItemsWithTitles:self.endpoints.count ? self.endpoints : @[@"Aucun port MIDI"]];
    [row.endpointMenu selectItemWithTitle:[self defaultEndpointForIndex:index]];
    [line addSubview:row.endpointMenu];

    row.channelMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(427, 7, 75, 27) pullsDown:NO];
    [row.channelMenu addItemWithTitle:@"Tous"];
    for (NSUInteger channel = 1; channel <= 16; channel++) [row.channelMenu addItemWithTitle:[NSString stringWithFormat:@"%lu", (unsigned long)channel]];
    [row.channelMenu selectItemWithTitle:@"1"];
    [line addSubview:row.channelMenu];

    row.delayField = [[NSTextField alloc] initWithFrame:NSMakeRect(510, 8, 65, 25)];
    row.delayField.stringValue = @"80";
    row.delayField.alignment = NSTextAlignmentCenter;
    [line addSubview:row.delayField];
    row.statusLabel = [self label:@"ARRÊTÉE" frame:NSMakeRect(585, 11, 128, 20) size:10 bold:YES];
    row.statusLabel.textColor = [NSColor colorWithRed:0.95 green:0.55 blue:0.25 alpha:1.0];
    [line addSubview:row.statusLabel];
    if (index < self.savedConfigs.count) {
        NSDictionary *config = self.savedConfigs[index];
        NSString *name = config[@"name"];
        NSString *endpoint = config[@"endpoint"];
        NSString *channel = config[@"channel"];
        NSNumber *delay = config[@"delay"];
        if (name.length) row.nameField.stringValue = name;
        if ([self.endpoints containsObject:endpoint]) [row.endpointMenu selectItemWithTitle:endpoint];
        if ([row.channelMenu itemWithTitle:channel]) [row.channelMenu selectItemWithTitle:channel];
        if (delay) row.delayField.stringValue = delay.stringValue;
    }
    [self.rows addObject:row];
    [self updateSummary];
}

- (NSString *)simulatorPath {
    NSString *executableDirectory = NSProcessInfo.processInfo.arguments.firstObject.stringByDeletingLastPathComponent;
    return [executableDirectory stringByAppendingPathComponent:@"CLYamahaConsoleSimulator"];
}

- (void)startRow:(CLYamahaRow *)row {
    if (row.task.running) return;
    NSString *tool = [self simulatorPath];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:tool]) {
        row.statusLabel.stringValue = @"OUTIL ABSENT";
        return;
    }
    NSInteger delay = MAX(0, row.delayField.integerValue);
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
        @"--label", row.nameField.stringValue.length ? row.nameField.stringValue : @"Yamaha",
        @"--endpoint", row.endpointMenu.titleOfSelectedItem ?: @"",
        @"--delay-ms", [NSString stringWithFormat:@"%ld", (long)delay]
    ]];
    if (![row.channelMenu.titleOfSelectedItem isEqualToString:@"Tous"]) {
        [arguments addObjectsFromArray:@[@"--channel", row.channelMenu.titleOfSelectedItem]];
    }
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = arguments;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak CLYamahaRow *weakRow = row;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CLYamahaRow *strongRow = weakRow;
            if (!strongRow || strongRow.task != finished) return;
            strongRow.task = nil;
            strongRow.power.state = NSControlStateValueOff;
            strongRow.statusLabel.stringValue = finished.terminationStatus == 0 ? @"ARRÊTÉE" : @"ERREUR";
            strongRow.statusLabel.textColor = finished.terminationStatus == 0 ? [NSColor orangeColor] : [NSColor redColor];
            [self updateSummary];
        });
    };
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        row.power.state = NSControlStateValueOff;
        row.statusLabel.stringValue = @"ERREUR";
        row.statusLabel.textColor = NSColor.redColor;
        return;
    }
    row.task = task;
    row.statusLabel.stringValue = @"ACTIVE";
    row.statusLabel.textColor = [NSColor colorWithRed:0.25 green:0.90 blue:0.48 alpha:1.0];
    [self updateSummary];
}

- (void)stopRow:(CLYamahaRow *)row {
    if (row.task.running) [row.task terminate];
    row.task = nil;
    row.power.state = NSControlStateValueOff;
    row.statusLabel.stringValue = @"ARRÊTÉE";
    row.statusLabel.textColor = NSColor.orangeColor;
    [self updateSummary];
}

- (void)toggleConsole:(NSButton *)sender {
    CLYamahaRow *row = self.rows[(NSUInteger)sender.tag];
    sender.state == NSControlStateValueOn ? [self startRow:row] : [self stopRow:row];
}
- (void)addConsole:(id)sender { (void)sender; [self addRowWithDefaults:self.rows.count]; }
- (void)startAll:(id)sender { (void)sender; for (CLYamahaRow *row in self.rows) { row.power.state = NSControlStateValueOn; [self startRow:row]; } }
- (void)stopAll:(id)sender { (void)sender; for (CLYamahaRow *row in self.rows) [self stopRow:row]; }
- (void)refreshPorts:(id)sender {
    (void)sender;
    self.endpoints = CLMidiEndpointNames();
    for (CLYamahaRow *row in self.rows) {
        NSString *selected = row.endpointMenu.titleOfSelectedItem;
        [row.endpointMenu removeAllItems];
        [row.endpointMenu addItemsWithTitles:self.endpoints.count ? self.endpoints : @[@"Aucun port MIDI"]];
        if ([self.endpoints containsObject:selected]) [row.endpointMenu selectItemWithTitle:selected];
    }
}
- (void)updateSummary {
    NSUInteger active = 0;
    for (CLYamahaRow *row in self.rows) if (row.task.running) active++;
    self.summary.stringValue = [NSString stringWithFormat:@"%lu console%@ configurée%@ · %lu active%@",
                                (unsigned long)self.rows.count, self.rows.count > 1 ? @"s" : @"",
                                self.rows.count > 1 ? @"s" : @"", (unsigned long)active, active > 1 ? @"s" : @""];
}
- (void)saveConfiguration {
    NSMutableArray<NSDictionary *> *configs = [NSMutableArray array];
    for (CLYamahaRow *row in self.rows) {
        [configs addObject:@{
            @"name": row.nameField.stringValue ?: @"",
            @"endpoint": row.endpointMenu.titleOfSelectedItem ?: @"",
            @"channel": row.channelMenu.titleOfSelectedItem ?: @"Tous",
            @"delay": @(MAX(0, row.delayField.integerValue))
        }];
    }
    [NSUserDefaults.standardUserDefaults setObject:configs forKey:@"CLYamahaSimulatorConsoles"];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    [self saveConfiguration];
    for (CLYamahaRow *row in self.rows) if (row.task.running) [row.task terminate];
    return NSTerminateNow;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
@end

int main(int argc, const char *argv[]) {
    (void)argc; (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        CLYamahaSimulatorDelegate *delegate = [[CLYamahaSimulatorDelegate alloc] init];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
