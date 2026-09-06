#import <AppKit/AppKit.h>
#import "CLMIDIAnalyzerModel.h"
#import "CLMIDICommandInterpreter.h"

@interface CLMIDIAnalyzerAppDelegate : NSObject
    <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, CLCommandTraceReceiver>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextView *detailView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) NSPopUpButton *retentionButton;
@property (nonatomic, strong) NSPopUpButton *typeFilterButton;
@property (nonatomic, strong) NSPopUpButton *channelFilterButton;
@property (nonatomic, strong) NSTextField *sourceFilterField;
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) CLMIDICore *core;
@property (nonatomic, strong) CLMIDIAnalyzerSession *session;
@property (nonatomic, strong) CLMIDIAnalyzerPacketParser *packetParser;
@property (nonatomic, strong) CLMIDICommandInterpreter *commandInterpreter;
@property (nonatomic, strong) NSMutableArray<CLMIDIEvent *> *pendingEvents;
@property (nonatomic, strong) NSMutableArray<CLCommand *> *pendingCommands;
@property (nonatomic, strong) NSMutableArray<CLMIDIEvent *> *pendingCommandEvents;
@property (nonatomic) BOOL flushScheduled;
@end


@implementation CLMIDIAnalyzerAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    self.session = [CLMIDIAnalyzerSession new];
    self.packetParser = [CLMIDIAnalyzerPacketParser new];
    self.commandInterpreter = [CLMIDICommandInterpreter new];
    self.pendingEvents = [NSMutableArray array];
    self.pendingCommands = [NSMutableArray array];
    self.pendingCommandEvents = [NSMutableArray array];
    [self buildMenu];
    [self buildWindow];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)buildMenu
{
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [menu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    [appMenu addItemWithTitle:@"Quit CL MIDI Analyzer"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSApp.mainMenu = menu;
}

- (void)buildWindow
{
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1120, 720)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"CL MIDI Analyzer";
    self.window.minSize = NSMakeSize(820, 560);
    [self.window center];

    NSView *content = self.window.contentView;
    NSStackView *root = [NSStackView new];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.spacing = 10;
    root.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor]
    ]];

    [root addArrangedSubview:[self buildHeader]];
    [root addArrangedSubview:[self buildToolbar]];
    [root addArrangedSubview:[self buildFilterBar]];
    NSSplitView *splitView = [self buildSplitView];
    [root addArrangedSubview:splitView];
    [splitView.heightAnchor constraintGreaterThanOrEqualToConstant:440].active = YES;

}

- (NSView *)buildHeader
{
    NSStackView *header = [NSStackView new];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.spacing = 12;
    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 128, 58)];
    logo.image = [[NSImage alloc] initWithContentsOfFile:
        [NSBundle.mainBundle pathForResource:@"paradis_latin_logo" ofType:@"jpg"]];
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    [logo.widthAnchor constraintEqualToConstant:128].active = YES;
    [logo.heightAnchor constraintEqualToConstant:58].active = YES;
    NSTextField *title = [NSTextField labelWithString:@"CL MIDI ANALYZER"];
    title.font = [NSFont boldSystemFontOfSize:17];
    title.textColor = [NSColor colorWithRed:0.224 green:0.455 blue:0.847 alpha:1.0];
    NSTextField *subtitle = [NSTextField labelWithString:@"Inspection CoreMIDI · captures · diagnostics"];
    subtitle.textColor = NSColor.secondaryLabelColor;
    NSStackView *titles = [NSStackView stackViewWithViews:@[title, subtitle]];
    titles.orientation = NSUserInterfaceLayoutOrientationVertical;
    titles.spacing = 2;
    [header addArrangedSubview:logo];
    [header addArrangedSubview:titles];
    return header;
}

- (NSView *)buildToolbar
{
    NSStackView *toolbar = [NSStackView new];
    toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    toolbar.spacing = 8;

    self.startButton = [NSButton buttonWithTitle:@"Start Monitoring"
                                          target:self
                                          action:@selector(startMonitoring:)];
    self.startButton.bezelStyle = NSBezelStyleRounded;
    self.stopButton = [NSButton buttonWithTitle:@"Stop Monitoring"
                                         target:self
                                         action:@selector(stopMonitoring:)];
    self.stopButton.enabled = NO;
    NSButton *clear = [NSButton buttonWithTitle:@"Clear"
                                         target:self
                                         action:@selector(clearLog:)];
    NSButton *save = [NSButton buttonWithTitle:@"Export CSV…"
                                        target:self
                                        action:@selector(saveLog:)];
    NSButton *json = [NSButton buttonWithTitle:@"Export JSON…" target:self action:@selector(exportJSON:)];
    NSButton *compare = [NSButton buttonWithTitle:@"Compare Capture…" target:self action:@selector(compareCapture:)];

    self.retentionButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.retentionButton addItemsWithTitles:@[@"10 000 events", @"50 000 events", @"Unlimited"]];
    self.retentionButton.target = self;
    self.retentionButton.action = @selector(changeRetention:);

    self.statusLabel = [NSTextField labelWithString:@"Stopped"];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self.statusLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    [toolbar addArrangedSubview:self.startButton];
    [toolbar addArrangedSubview:self.stopButton];
    [toolbar addArrangedSubview:clear];
    [toolbar addArrangedSubview:save];
    [toolbar addArrangedSubview:json];
    [toolbar addArrangedSubview:compare];
    [toolbar addArrangedSubview:self.retentionButton];
    [toolbar addArrangedSubview:self.statusLabel];
    return toolbar;
}

- (NSView *)buildFilterBar
{
    NSStackView *filters = [NSStackView new];
    filters.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    filters.spacing = 8;
    self.typeFilterButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.typeFilterButton addItemsWithTitles:@[
        @"Tous les types", @"Note Off", @"Note On", @"Polyphonic Key Pressure",
        @"Control Change", @"Program Change", @"Channel Pressure", @"Pitch Bend",
        @"System Exclusive", @"MIDI Time Code Quarter Frame", @"Song Position Pointer",
        @"Song Select", @"Tune Request", @"Timing Clock", @"Start", @"Continue",
        @"Stop", @"Active Sensing", @"System Reset", @"Data/Running Status", @"Unknown"
    ]];
    self.typeFilterButton.target = self;
    self.typeFilterButton.action = @selector(filtersChanged:);
    self.channelFilterButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.channelFilterButton addItemWithTitle:@"Tous les canaux"];
    for (NSInteger channel = 1; channel <= 16; channel++) [self.channelFilterButton addItemWithTitle:[NSString stringWithFormat:@"Canal %ld", (long)channel]];
    self.channelFilterButton.target = self;
    self.channelFilterButton.action = @selector(filtersChanged:);
    self.sourceFilterField = [NSTextField new];
    self.sourceFilterField.placeholderString = @"Filtrer la source";
    self.sourceFilterField.target = self;
    self.sourceFilterField.action = @selector(filtersChanged:);
    [self.sourceFilterField.widthAnchor constraintEqualToConstant:190].active = YES;
    self.searchField = [NSSearchField new];
    self.searchField.placeholderString = @"Rechercher commande, description ou hex";
    self.searchField.target = self;
    self.searchField.action = @selector(filtersChanged:);
    [self.searchField.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;
    NSButton *reset = [NSButton buttonWithTitle:@"Réinitialiser" target:self action:@selector(resetFilters:)];
    [filters addArrangedSubview:[NSTextField labelWithString:@"Filtres"]];
    [filters addArrangedSubview:self.typeFilterButton];
    [filters addArrangedSubview:self.channelFilterButton];
    [filters addArrangedSubview:self.sourceFilterField];
    [filters addArrangedSubview:self.searchField];
    [filters addArrangedSubview:reset];
    return filters;
}

- (void)filtersChanged:(id)sender
{
    (void)sender;
    self.session.typeFilter = self.typeFilterButton.indexOfSelectedItem == 0 ? nil : self.typeFilterButton.titleOfSelectedItem;
    self.session.channelFilter = self.channelFilterButton.indexOfSelectedItem == 0 ? nil : @(self.channelFilterButton.indexOfSelectedItem);
    self.session.sourceFilter = self.sourceFilterField.stringValue;
    self.session.searchText = self.searchField.stringValue;
    [self.tableView reloadData];
    self.detailView.string = @"";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu / %lu événements visibles",
        (unsigned long)self.session.visibleRecords.count, (unsigned long)self.session.records.count];
}

- (void)resetFilters:(id)sender
{
    (void)sender;
    [self.typeFilterButton selectItemAtIndex:0];
    [self.channelFilterButton selectItemAtIndex:0];
    self.sourceFilterField.stringValue = @"";
    self.searchField.stringValue = @"";
    [self filtersChanged:nil];
}

- (NSSplitView *)buildSplitView
{
    NSSplitView *split = [NSSplitView new];
    split.vertical = NO;
    split.dividerStyle = NSSplitViewDividerStyleThin;

    NSScrollView *tableScroll = [NSScrollView new];
    tableScroll.hasVerticalScroller = YES;
    tableScroll.hasHorizontalScroller = YES;
    tableScroll.borderType = NSBezelBorder;
    self.tableView = [NSTableView new];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    self.tableView.allowsMultipleSelection = NO;
    [self addColumn:@"time" title:@"Heure" width:105];
    [self addColumn:@"direction" title:@"Direction" width:70];
    [self addColumn:@"source" title:@"Source" width:180];
    [self addColumn:@"command" title:@"Type de commande" width:135];
    [self addColumn:@"channel" title:@"Canal" width:65];
    [self addColumn:@"description" title:@"Description" width:220];
    [self addColumn:@"hex" title:@"Octets hexadécimaux" width:240];
    tableScroll.documentView = self.tableView;

    NSScrollView *detailScroll = [NSScrollView new];
    detailScroll.hasVerticalScroller = YES;
    detailScroll.borderType = NSBezelBorder;
    self.detailView = [[NSTextView alloc] initWithFrame:NSZeroRect];
    self.detailView.editable = NO;
    self.detailView.selectable = YES;
    self.detailView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.detailView.string = @"Select a command to inspect CLCommand, CLMIDIEvent and CLMIDIPacket.";
    detailScroll.documentView = self.detailView;

    [split addSubview:tableScroll];
    [split addSubview:detailScroll];
    [tableScroll.heightAnchor constraintGreaterThanOrEqualToConstant:270].active = YES;
    [detailScroll.heightAnchor constraintGreaterThanOrEqualToConstant:160].active = YES;
    return split;
}

- (void)addColumn:(NSString *)identifier title:(NSString *)title width:(CGFloat)width
{
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
    column.title = title;
    column.width = width;
    column.minWidth = 55;
    [self.tableView addTableColumn:column];
}

- (void)startMonitoring:(id)sender
{
    (void)sender;
    if (self.core != nil) return;
    self.commandInterpreter = [CLMIDICommandInterpreter new];
    self.core = [CLMIDICore new];
    __weak typeof(self) weakSelf = self;
    self.core.eventHandler = ^(CLMIDIEvent *event) {
        [weakSelf receiveEvent:event];
    };
    if (![self.core startMonitoring])
    {
        self.core = nil;
        self.statusLabel.stringValue = @"Unable to start";
        NSBeep();
        return;
    }
    self.statusLabel.stringValue = @"Monitoring";
    self.startButton.enabled = NO;
    self.stopButton.enabled = YES;
}

- (void)stopMonitoring:(id)sender
{
    (void)sender;
    self.core.eventHandler = nil;
    [self.core stopMonitoring];
    self.core = nil;
    [self.packetParser reset];
    self.statusLabel.stringValue = @"Stopped";
    self.startButton.enabled = YES;
    self.stopButton.enabled = NO;
}

- (void)clearLog:(id)sender
{
    (void)sender;
    @synchronized (self)
    {
        [self.pendingEvents removeAllObjects];
        [self.pendingCommands removeAllObjects];
        [self.pendingCommandEvents removeAllObjects];
    }
    [self.session clear];
    [self.tableView reloadData];
    self.detailView.string = @"";
}

- (void)changeRetention:(id)sender
{
    (void)sender;
    NSArray<NSNumber *> *limits = @[@10000, @50000, @0];
    self.session.maximumRecordCount = limits[(NSUInteger)self.retentionButton.indexOfSelectedItem].unsignedIntegerValue;
    [self.tableView reloadData];
}

- (void)saveLog:(id)sender
{
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"CL_MIDI_Analyzer_Capture.csv";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSMutableString *contents = [@"Heure,Direction,Source,Commande,Canal,Description,Hex\n" mutableCopy];
        for (CLMIDIAnalyzerRecord *record in self.session.visibleRecords) {
            NSMutableArray *fields = [NSMutableArray array];
            for (NSString *value in @[record.timeText, record.direction, record.sourceText,
                    record.commandTypeText, record.channelText, record.descriptionText, record.hexText]) {
                NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
                [fields addObject:[NSString stringWithFormat:@"\"%@\"", escaped]];
            }
            [contents appendFormat:@"%@\n", [fields componentsJoinedByString:@","]];
        }
        NSError *error = nil;
        if (![contents writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error])
        {
            [self.window presentError:error];
        }
    }];
}

- (NSArray<NSDictionary *> *)JSONRecords
{
    NSMutableArray *payload = [NSMutableArray array];
    for (CLMIDIAnalyzerRecord *record in self.session.visibleRecords) {
        [payload addObject:@{
            @"time": record.timeText,
            @"direction": record.direction,
            @"source": record.sourceText,
            @"command_type": record.commandTypeText,
            @"channel": record.channelText,
            @"description": record.descriptionText,
            @"hex": record.hexText,
        }];
    }
    return payload;
}

- (void)exportJSON:(id)sender
{
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"CL_MIDI_Analyzer_Capture.json";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSDictionary *capture = @{
            @"format": @"cl-midi-analyzer-capture",
            @"version": @2,
            @"created_at": @([[NSDate date] timeIntervalSince1970]),
            @"records": [self JSONRecords],
        };
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:capture options:NSJSONWritingPrettyPrinted error:&error];
        if (!data || ![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) [self.window presentError:error];
    }];
}

- (void)compareCapture:(id)sender
{
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"json"];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
        NSDictionary *capture = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
        NSArray *reference = [capture[@"records"] isKindOfClass:NSArray.class] ? capture[@"records"] : nil;
        if (!reference) { [self.window presentError:error ?: [NSError errorWithDomain:@"CLMIDIAnalyzer" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Capture JSON incompatible"}]]; return; }
        NSInteger delta = (NSInteger)self.session.visibleRecords.count - (NSInteger)reference.count;
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Comparaison de captures";
        alert.informativeText = [NSString stringWithFormat:
            @"Capture actuelle : %lu événements\nCapture de référence : %lu événements\nÉcart : %@%ld",
            (unsigned long)self.session.visibleRecords.count, (unsigned long)reference.count,
            delta > 0 ? @"+" : @"", (long)delta];
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    }];
}

- (void)receiveCommand:(CLCommand *)command
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%@ (trace unavailable)", command.name];
    });
}

- (void)receiveCommand:(CLCommand *)command originatingEvent:(CLMIDIEvent *)event
{
    @synchronized (self)
    {
        [self.pendingCommands addObject:command];
        [self.pendingCommandEvents addObject:event];
        [self scheduleFlushLocked];
    }
}

- (void)receiveEvent:(CLMIDIEvent *)event
{
    @synchronized (self)
    {
        for (CLMIDIEvent *messageEvent in [self.packetParser eventsForPacket:event.packet])
        {
            [self.pendingEvents addObject:messageEvent];
            for (CLCommand *command in [self.commandInterpreter commandsForEvent:messageEvent])
            {
                [self.pendingCommands addObject:command];
                [self.pendingCommandEvents addObject:messageEvent];
            }
        }
        [self scheduleFlushLocked];
    }
}

- (void)scheduleFlushLocked
{
    if (self.flushScheduled) return;
    self.flushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 16 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{ [self flushPendingUpdates]; });
}

- (void)flushPendingUpdates
{
    NSArray<CLMIDIEvent *> *events;
    NSArray<CLCommand *> *commands;
    NSArray<CLMIDIEvent *> *commandEvents;
    @synchronized (self)
    {
        events = self.pendingEvents.copy;
        commands = self.pendingCommands.copy;
        commandEvents = self.pendingCommandEvents.copy;
        [self.pendingEvents removeAllObjects];
        [self.pendingCommands removeAllObjects];
        [self.pendingCommandEvents removeAllObjects];
        self.flushScheduled = NO;
    }

    NSUInteger oldCount = self.session.visibleRecords.count;
    NSMutableArray<CLMIDIAnalyzerRecord *> *records = [NSMutableArray arrayWithCapacity:events.count];
    NSDate *timestamp = [NSDate date];
    for (CLMIDIEvent *event in events)
    {
        [records addObject:[[CLMIDIAnalyzerRecord alloc]
            initWithCommand:nil event:event direction:@"RX" timestamp:timestamp]];
    }
    [self.session addRecords:records];
    NSUInteger newCount = self.session.visibleRecords.count;

    BOOL filtersActive = self.session.typeFilter.length || self.session.sourceFilter.length || self.session.searchText.length;
    if (records.count > 0 && filtersActive)
    {
        [self.tableView reloadData];
    }
    else if (records.count > 0)
    {
        NSUInteger discardedCount = oldCount + records.count - newCount;
        NSUInteger removedCount = MIN(oldCount, discardedCount);
        NSUInteger retainedOldCount = oldCount - removedCount;
        NSUInteger insertedCount = newCount - retainedOldCount;
        [self.tableView beginUpdates];
        if (removedCount > 0)
            [self.tableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, removedCount)]
                                 withAnimation:NSTableViewAnimationEffectNone];
        if (insertedCount > 0)
            [self.tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:
                NSMakeRange(newCount - insertedCount, insertedCount)]
                                 withAnimation:NSTableViewAnimationEffectNone];
        [self.tableView endUpdates];
    }

    NSMutableIndexSet *changedRows = [NSMutableIndexSet indexSet];
    for (NSUInteger index = 0; index < commands.count; index++)
    {
        CLMIDIEvent *event = commandEvents[index];
        CLMIDIAnalyzerRecord *record = [self.session recordForEvent:event];
        if (record == nil) continue;
        [record applyCommand:commands[index]];
        NSUInteger row = [self.session.visibleRecords indexOfObjectIdenticalTo:record];
        if (row != NSNotFound) [changedRows addIndex:row];
    }
    if (filtersActive && commands.count > 0)
    {
        // Les enregistrements sont ajoutés avant leur enrichissement CLCommand.
        // Un filtre PROGRAM peut donc les exclure à l'état brut `(none)` ; il
        // faut recalculer immédiatement après applyCommand, sans attendre le
        // prochain message MIDI (souvent PAUSE ou STOP).
        [self.session refreshVisibleRecords];
        newCount = self.session.visibleRecords.count;
        [self.tableView reloadData];
    }
    if (changedRows.count > 0)
    {
        NSIndexSet *columns = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.tableView.tableColumns.count)];
        [self.tableView reloadDataForRowIndexes:changedRows columnIndexes:columns];
    }

    NSInteger lastRow = (NSInteger)newCount - 1;
    if (lastRow >= 0 && records.count > 0) [self.tableView scrollRowToVisible:lastRow];
    self.statusLabel.stringValue = [NSString stringWithFormat:@"Monitoring · %lu events",
        (unsigned long)newCount];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    NSArray<CLMIDIAnalyzerRecord *> *visibleRecords = self.session.visibleRecords;
    return (NSInteger)visibleRecords.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row
{
    NSTextField *cell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    if (cell == nil)
    {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = tableColumn.identifier;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    NSArray<CLMIDIAnalyzerRecord *> *visibleRecords = self.session.visibleRecords;
    CLMIDIAnalyzerRecord *record = visibleRecords[(NSUInteger)row];
    NSDictionary<NSString *, NSString *> *values = @{
        @"time": record.timeText, @"direction": record.direction,
        @"source": record.sourceText, @"command": record.commandTypeText,
        @"channel": record.channelText, @"description": record.descriptionText,
        @"hex": record.hexText
    };
    cell.stringValue = values[tableColumn.identifier] ?: @"";
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    (void)notification;
    NSInteger row = self.tableView.selectedRow;
    NSArray<CLMIDIAnalyzerRecord *> *visibleRecords = self.session.visibleRecords;
    if (row < 0 || row >= (NSInteger)visibleRecords.count) return;
    self.detailView.string = visibleRecords[(NSUInteger)row].detailText;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

@end


int main(void)
{
    @autoreleasepool
    {
        NSApplication *application = NSApplication.sharedApplication;
        CLMIDIAnalyzerAppDelegate *delegate = [CLMIDIAnalyzerAppDelegate new];
        application.delegate = delegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}
