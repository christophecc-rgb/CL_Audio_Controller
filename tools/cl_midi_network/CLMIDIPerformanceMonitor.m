#import <AppKit/AppKit.h>
#import <CoreMIDI/CoreMIDI.h>
#import <stdatomic.h>

static atomic_ulong CLMessageCount;
static atomic_ulong CLByteCount;
static atomic_ulong CLProgramChangeCount;
static atomic_int CLLastProgram;
static atomic_int CLLastProgramChannel;

static void CLMidiRead(const MIDIPacketList *packets, void *context, void *connection) {
    (void)context; (void)connection;
    const MIDIPacket *packet = &packets->packet[0];
    for (UInt32 p = 0; p < packets->numPackets; p++) {
        atomic_fetch_add(&CLByteCount, packet->length);
        UInt16 index = 0;
        while (index < packet->length) {
            UInt8 status = packet->data[index];
            NSUInteger length = 1;
            if ((status & 0xF0) == 0xC0 || (status & 0xF0) == 0xD0) length = 2;
            else if ((status & 0x80) != 0 && status < 0xF0) length = 3;
            else if (status == 0xF1 || status == 0xF3) length = 2;
            else if (status == 0xF2) length = 3;
            atomic_fetch_add(&CLMessageCount, 1);
            if ((status & 0xF0) == 0xC0 && index + 1 < packet->length) {
                atomic_fetch_add(&CLProgramChangeCount, 1);
                atomic_store(&CLLastProgram, packet->data[index + 1]);
                atomic_store(&CLLastProgramChannel, (status & 0x0F) + 1);
            }
            index += MIN(length, packet->length - index);
        }
        packet = MIDIPacketNext(packet);
    }
}

static void CLInstallApplicationMenu(void) {
    NSMenu *main = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *root = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quitter CL MIDI Performance Monitor" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    [menu addItem:quit]; root.submenu = menu; [main addItem:root]; NSApp.mainMenu = main;
}

@interface CLPerformanceDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSTextField *headline;
@property NSTextField *abletonLabel;
@property NSTextField *clToolsLabel;
@property NSTextField *midiLabel;
@property NSTextField *peakLabel;
@property NSTextField *reportLabel;
@property NSButton *toggleButton;
@property NSTimer *timer;
@property NSFileHandle *report;
@property NSString *reportPath;
@property MIDIClientRef midiClient;
@property MIDIPortRef midiInput;
@property BOOL measuring;
@property double peakCPU;
@property unsigned long peakMessages;
@property unsigned long peakBytes;
@property unsigned long lastMessages;
@property unsigned long lastBytes;
@property unsigned long lastPrograms;
@end

@implementation CLPerformanceDelegate

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = text; field.editable = NO; field.bordered = NO; field.drawsBackground = NO;
    field.textColor = [NSColor colorWithWhite:0.86 alpha:1];
    field.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return field;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification; CLInstallApplicationMenu();
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,520,390)
                                              styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI Performance Monitor";
    self.window.backgroundColor = [NSColor colorWithRed:.035 green:.045 blue:.06 alpha:1];
    [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
    NSView *view = self.window.contentView;
    self.headline = [self label:@"PRÊT À MESURER" frame:NSMakeRect(24,325,470,36) size:24 bold:YES];
    self.headline.textColor = [NSColor colorWithRed:.35 green:.85 blue:.55 alpha:1]; [view addSubview:self.headline];
    [view addSubview:[self label:@"Mesure passive · aucun périphérique ajouté dans Ableton" frame:NSMakeRect(25,302,470,20) size:11 bold:NO]];
    self.abletonLabel = [self label:@"Ableton · CPU macOS — · total Mac —" frame:NSMakeRect(24,252,472,30) size:15 bold:YES]; [view addSubview:self.abletonLabel];
    self.clToolsLabel = [self label:@"Outils CL · CPU — · mémoire —" frame:NSMakeRect(24,218,472,28) size:12 bold:NO]; [view addSubview:self.clToolsLabel];
    self.midiLabel = [self label:@"MIDI · — msg/s · — octets/s · — Program Change" frame:NSMakeRect(24,174,472,36) size:14 bold:YES]; [view addSubview:self.midiLabel];
    self.peakLabel = [self label:@"Pics · en attente" frame:NSMakeRect(24,137,472,28) size:12 bold:NO]; [view addSubview:self.peakLabel];
    self.reportLabel = [self label:@"Le rapport sera enregistré sur le Bureau." frame:NSMakeRect(24,105,472,28) size:10 bold:NO]; [view addSubview:self.reportLabel];
    self.toggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(24,35,472,58)];
    self.toggleButton.title = @"DÉMARRER LA MESURE"; self.toggleButton.bezelStyle = NSBezelStyleRounded;
    self.toggleButton.target = self; self.toggleButton.action = @selector(toggle:); [view addSubview:self.toggleButton];
}

- (NSArray<NSNumber *> *)abletonUsage {
    NSTask *task = [[NSTask alloc] init]; task.executableURL = [NSURL fileURLWithPath:@"/bin/ps"];
    task.arguments = @[@"-axo", @"%cpu=,rss=,command="]; NSPipe *pipe = NSPipe.pipe; task.standardOutput = pipe;
    NSError *error = nil; if (![task launchAndReturnError:&error]) return @[@0,@0];
    // Vider le pipe pendant l'exécution. Attendre d'abord peut bloquer si la
    // liste des processus remplit le tampon avant que `ps` ne se termine.
    NSData *processData = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    NSString *output = [[NSString alloc] initWithData:processData encoding:NSUTF8StringEncoding];
    double cpu = 0, clCPU = 0; unsigned long rss = 0, clRSS = 0;
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSScanner *scanner = [NSScanner scannerWithString:line]; double value = 0; long long memory = 0;
        if (![scanner scanDouble:&value] || ![scanner scanLongLong:&memory]) continue;
        if ([line rangeOfString:@"Ableton Live" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            cpu += value; rss += (unsigned long)MAX(0,memory);
        } else if (
            [line rangeOfString:@"CL Audio Controller" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [line rangeOfString:@"CL MIDI" options:NSCaseInsensitiveSearch].location != NSNotFound ||
            [line rangeOfString:@"CLYamaha" options:NSCaseInsensitiveSearch].location != NSNotFound
        ) {
            clCPU += value; clRSS += (unsigned long)MAX(0,memory);
        }
    }
    return @[@(cpu), @(rss), @(clCPU), @(clRSS)];
}

- (void)startMidi {
    atomic_store(&CLMessageCount,0); atomic_store(&CLByteCount,0); atomic_store(&CLProgramChangeCount,0);
    atomic_store(&CLLastProgram,-1); atomic_store(&CLLastProgramChannel,-1);
    MIDIClientCreate(CFSTR("CL Performance Monitor"), NULL, NULL, &_midiClient);
    MIDIInputPortCreate(self.midiClient, CFSTR("CL Passive MIDI Input"), CLMidiRead, NULL, &_midiInput);
    for (ItemCount index=0; index<MIDIGetNumberOfSources(); index++) MIDIPortConnectSource(self.midiInput, MIDIGetSource(index), NULL);
}

- (void)toggle:(id)sender { (void)sender; self.measuring ? [self stop] : [self start]; }

- (void)start {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init]; formatter.dateFormat = @"yyyy-MM-dd_HHmmss";
    self.reportPath = [NSHomeDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"Desktop/CL_Performance_%@.csv",[formatter stringFromDate:NSDate.date]]];
    [NSFileManager.defaultManager createFileAtPath:self.reportPath contents:[@"timestamp,ableton_cpu_one_core_percent,ableton_cpu_total_mac_percent,ableton_memory_mb,cl_tools_cpu_one_core_percent,cl_tools_cpu_total_mac_percent,cl_tools_memory_mb,midi_messages_per_second,midi_bytes_per_second,program_changes_per_second,program_changes_total,last_program_channel,last_program_number\n" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
    self.report = [NSFileHandle fileHandleForWritingAtPath:self.reportPath]; [self.report seekToEndOfFile];
    self.peakCPU=0; self.peakMessages=0; self.peakBytes=0; self.lastMessages=0; self.lastBytes=0; self.lastPrograms=0;
    [self startMidi]; self.measuring=YES; self.toggleButton.title=@"ARRÊTER ET ENREGISTRER";
    self.headline.stringValue=@"MESURE EN COURS"; self.headline.textColor=[NSColor colorWithRed:.35 green:.85 blue:.55 alpha:1];
    self.reportLabel.stringValue=[@"Rapport : " stringByAppendingString:self.reportPath.lastPathComponent];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(sample:) userInfo:nil repeats:YES]; [self sample:nil];
}

- (void)sample:(NSTimer *)timer {
    (void)timer; NSArray<NSNumber *> *usage=[self abletonUsage];
    double cpu=usage[0].doubleValue, memory=usage[1].doubleValue/1024.0;
    double clCPU=usage[2].doubleValue, clMemory=usage[3].doubleValue/1024.0;
    NSUInteger logicalProcessors=MAX((NSUInteger)1,NSProcessInfo.processInfo.processorCount);
    double totalMacCPU=cpu/logicalProcessors, clTotalMacCPU=clCPU/logicalProcessors;
    unsigned long totalMessages=atomic_load(&CLMessageCount), totalBytes=atomic_load(&CLByteCount), totalPrograms=atomic_load(&CLProgramChangeCount);
    int lastProgram=atomic_load(&CLLastProgram), lastProgramChannel=atomic_load(&CLLastProgramChannel);
    unsigned long messages=totalMessages-self.lastMessages, bytes=totalBytes-self.lastBytes, programs=totalPrograms-self.lastPrograms;
    self.lastMessages=totalMessages; self.lastBytes=totalBytes; self.lastPrograms=totalPrograms;
    self.peakCPU=MAX(self.peakCPU,cpu); self.peakMessages=MAX(self.peakMessages,messages); self.peakBytes=MAX(self.peakBytes,bytes);
    self.abletonLabel.stringValue=[NSString stringWithFormat:@"Ableton · %.1f %% d’un cœur · %.1f %% du Mac",cpu,totalMacCPU];
    self.clToolsLabel.stringValue=[NSString stringWithFormat:@"Outils CL · %.1f %% d’un cœur · %.1f %% du Mac · %.0f Mo",clCPU,clTotalMacCPU,clMemory];
    NSString *lastProgramText = lastProgram >= 0
        ? [NSString stringWithFormat:@"dernier PC · ch.%d n°%d",lastProgramChannel,lastProgram]
        : @"aucun PC reçu";
    self.midiLabel.stringValue=[NSString stringWithFormat:@"MIDI · %lu msg/s · PC %lu/s · total %lu · %@",messages,programs,totalPrograms,lastProgramText];
    self.peakLabel.stringValue=[NSString stringWithFormat:@"Pics · CPU %.1f %% · MIDI %lu msg/s · %lu octets/s",self.peakCPU,self.peakMessages,self.peakBytes];
    BOOL red=cpu>=85||messages>=1000, orange=cpu>=60||messages>=250;
    self.headline.stringValue=red?@"CHARGE ÉLEVÉE":(orange?@"À SURVEILLER":@"MESURE NORMALE");
    self.headline.textColor=red?NSColor.systemRedColor:(orange?NSColor.systemOrangeColor:NSColor.systemGreenColor);
    NSString *line=[NSString stringWithFormat:@"%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%lu,%lu,%lu,%lu,%d,%d\n",NSDate.date.timeIntervalSince1970,cpu,totalMacCPU,memory,clCPU,clTotalMacCPU,clMemory,messages,bytes,programs,totalPrograms,lastProgramChannel,lastProgram];
    [self.report writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)stop {
    [self.timer invalidate]; self.timer=nil; if(self.midiInput) MIDIPortDispose(self.midiInput); if(self.midiClient) MIDIClientDispose(self.midiClient); self.midiInput=0; self.midiClient=0;
    [self.report closeFile]; self.report=nil; self.measuring=NO; self.toggleButton.title=@"DÉMARRER UNE NOUVELLE MESURE";
    self.headline.stringValue=@"RAPPORT ENREGISTRÉ"; self.headline.textColor=NSColor.systemGreenColor;
    self.reportLabel.stringValue=self.reportPath;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { (void)sender; if(self.measuring)[self stop]; return NSTerminateNow; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
@end

int main(int argc,const char *argv[]){(void)argc;(void)argv;@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;CLPerformanceDelegate *delegate=[[CLPerformanceDelegate alloc]init];app.delegate=delegate;[app setActivationPolicy:NSApplicationActivationPolicyRegular];[app run];}return 0;}
