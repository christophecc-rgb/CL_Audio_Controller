#import <AppKit/AppKit.h>
#import "CLMIDIAnalyzerModel.h"

@interface CLMIDIAnalyzerAppDelegate : NSObject
    <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, CLCommandTraceReceiver>
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSTextView *detailView;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSButton *startButton;
@property (nonatomic, strong) NSButton *stopButton;
@property (nonatomic, strong) CLMIDICore *core;
@property (nonatomic, strong) CLMIDIAnalyzerSession *session;
@end


@implementation CLMIDIAnalyzerAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    self.session = [CLMIDIAnalyzerSession new];
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

    [root addArrangedSubview:[self buildToolbar]];
    NSSplitView *splitView = [self buildSplitView];
    [root addArrangedSubview:splitView];
    [splitView.heightAnchor constraintGreaterThanOrEqualToConstant:440].active = YES;

    NSTextField *future = [NSTextField labelWithString:
        @"Prepared: type/source filters · search · JSON/CSV · session capture · capture comparison"];
    future.textColor = NSColor.secondaryLabelColor;
    future.font = [NSFont systemFontOfSize:11];
    [root addArrangedSubview:future];
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
    NSButton *save = [NSButton buttonWithTitle:@"Save Log…"
                                        target:self
                                        action:@selector(saveLog:)];

    self.statusLabel = [NSTextField labelWithString:@"Stopped"];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [self.statusLabel setContentHuggingPriority:NSLayoutPriorityDefaultLow
                                forOrientation:NSLayoutConstraintOrientationHorizontal];

    [toolbar addArrangedSubview:self.startButton];
    [toolbar addArrangedSubview:self.stopButton];
    [toolbar addArrangedSubview:clear];
    [toolbar addArrangedSubview:save];
    [toolbar addArrangedSubview:self.statusLabel];
    return toolbar;
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
    self.core = [CLMIDICore new];
    self.core.commandReceiver = self;
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
    [self.core stopMonitoring];
    self.core = nil;
    self.statusLabel.stringValue = @"Stopped";
    self.startButton.enabled = YES;
    self.stopButton.enabled = NO;
}

- (void)clearLog:(id)sender
{
    (void)sender;
    [self.session clear];
    [self.tableView reloadData];
    self.detailView.string = @"";
}

- (void)saveLog:(id)sender
{
    (void)sender;
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"CL_MIDI_Analyzer_Log.tsv";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSString *header = @"Heure\tDirection\tSource\tCommande\tCanal\tDescription\tHex\n";
        NSString *contents = [header stringByAppendingString:self.session.textLog];
        NSError *error = nil;
        if (![contents writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error])
        {
            [self.window presentError:error];
        }
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
    dispatch_async(dispatch_get_main_queue(), ^{
        CLMIDIAnalyzerRecord *record = [[CLMIDIAnalyzerRecord alloc]
            initWithCommand:command event:event direction:@"RX" timestamp:[NSDate date]];
        [self.session addRecord:record];
        [self.tableView reloadData];
        NSInteger row = (NSInteger)self.session.visibleRecords.count - 1;
        if (row >= 0) [self.tableView scrollRowToVisible:row];
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Monitoring · %lu commands",
            (unsigned long)self.session.records.count];
    });
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)self.session.visibleRecords.count;
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
    CLMIDIAnalyzerRecord *record = self.session.visibleRecords[(NSUInteger)row];
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
    if (row < 0 || row >= (NSInteger)self.session.visibleRecords.count) return;
    self.detailView.string = self.session.visibleRecords[(NSUInteger)row].detailText;
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
