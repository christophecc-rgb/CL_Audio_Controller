#import "../shared/CLMIDIEndpointNames.h"
#import <Cocoa/Cocoa.h>
#import <CoreMIDI/CoreMIDI.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <mach/mach_time.h>
#include <sys/socket.h>
#include <unistd.h>
#include "CLSyncMeterCore.h"
#include "CLSyncMIDIClock.h"

static NSString *const MTCSourceName=@CL_MIDI_MTC_IAC;
static double ClockNow(void) {
    static mach_timebase_info_data_t base;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&base); });
    return (double)mach_continuous_time()*base.numer/base.denom/1e9;
}
static NSString *Timecode(double seconds) {
    if (!isfinite(seconds)) return @"--:--:--:--";
    int h,m,s,f; secondsToTC(seconds,&h,&m,&s,&f);
    return [NSString stringWithFormat:@"%02d:%02d:%02d:%02d",h,m,s,f];
}
static NSString *MIDIName(MIDIEndpointRef ep) {
    CFStringRef name=NULL;
    MIDIObjectGetStringProperty(ep,kMIDIPropertyDisplayName,&name);
    if(!name) MIDIObjectGetStringProperty(ep,kMIDIPropertyName,&name);
    return name?CFBridgingRelease(name):@"";
}
static NSTextField *Label(NSString *text,CGFloat size,BOOL mono) {
    NSTextField *v=[NSTextField labelWithString:text];
    v.font=mono?[NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightMedium]:[NSFont systemFontOfSize:size weight:NSFontWeightMedium];
    v.textColor=NSColor.labelColor;
    v.lineBreakMode=NSLineBreakByWordWrapping;
    v.maximumNumberOfLines=0;
    return v;
}
static NSStackView *Stack(NSArray<NSView *> *views,NSUserInterfaceLayoutOrientation orientation,CGFloat gap) {
    NSStackView *v=[NSStackView stackViewWithViews:views];
    v.orientation=orientation; v.spacing=gap;
    v.alignment=orientation==NSUserInterfaceLayoutOrientationVertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;
    return v;
}
static NSView *Panel(NSView *content) {
    NSView *v=[NSView new]; v.wantsLayer=YES;
    v.layer.backgroundColor=[NSColor colorWithWhite:0.115 alpha:1].CGColor;
    v.layer.cornerRadius=10;
    content.translatesAutoresizingMaskIntoConstraints=NO; [v addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:14],
        [content.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-14],
        [content.topAnchor constraintEqualToAnchor:v.topAnchor constant:12],
        [content.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-12]]];
    return v;
}

@interface CLSyncMeter : NSObject<NSApplicationDelegate,NSTextFieldDelegate> {
    CLSyncMeterState _state;
    MIDIClientRef _client;
    MIDIPortRef _port;
    MIDIEndpointRef _source;
    double _lastDiscovery;
}
@property NSWindow *window;
@property NSTimer *timer;
@property dispatch_source_t udp;
@property NSString *midiError;
@property NSString *udpError;
@property NSTextField *chainLabel;
@property NSTextField *lockLabel,*sourceLabel,*offsetLabel,*framesLabel,*refLabel,*mtcLabel;
@property NSTextField *transportLabel,*statsLabel,*timingLabel,*proposalLabel,*audioMTC,*audioResult;
@property NSTextField *pdcField,*interfaceField,*measuredField;
@property NSButton *correctionButton;
@property BOOL diagnose;
- (void)consumeMIDI:(NSData *)data at:(double)now;
@end

static void MIDIRead(const MIDIPacketList *packets,void *context,void *connection) {
    CLSyncMeter *meter=(__bridge CLSyncMeter *)context;
    const MIDIPacket *packet=&packets->packet[0];
    for(UInt32 i=0;i<packets->numPackets;i++) {
        double now=CLSyncPacketTime(packet->timeStamp,ClockNow());
        NSData *data=[NSData dataWithBytes:packet->data length:packet->length];
        dispatch_async(dispatch_get_main_queue(), ^{ [meter consumeMIDI:data at:now]; });
        packet=MIDIPacketNext(packet);
    }
}

@implementation CLSyncMeter
- (void)consumeMIDI:(NSData *)data at:(double)now {
    CLSyncMIDIBytes(&_state,data.bytes,data.length,now);
}
- (void)discoverSource {
    if (!_client) {
        OSStatus result=MIDIClientCreate(CFSTR("CL Sync Meter — receive only"),NULL,NULL,&_client);
        if(result) { self.midiError=[NSString stringWithFormat:@"CoreMIDI indisponible (%d)",(int)result]; return; }
    }
    if (!_port) {
        OSStatus result=MIDIInputPortCreate(_client,CFSTR("MTC RX"),MIDIRead,(__bridge void *)self,&_port);
        if(result) { self.midiError=[NSString stringWithFormat:@"Entrée CoreMIDI indisponible (%d)",(int)result]; return; }
    }
    MIDIEndpointRef found=CLMIDIFindEndpoint(YES,MTCSourceName);
    if(found!=_source) {
        if(_source) MIDIPortDisconnectSource(_port,_source);
        _source=0; CLSyncBreak(&_state,true);
        if(found) {
            OSStatus result=MIDIPortConnectSource(_port,found,NULL);
            if(!result) _source=found;
            else { self.midiError=[NSString stringWithFormat:@"Connexion MIDI impossible (%d)",(int)result]; return; }
        }
    }
    self.midiError=_source?nil:@"Bus MTC absent — attente de la source";
}
- (void)listenUDP {
    if(self.udp) return;
    int fd=socket(AF_INET,SOCK_DGRAM,0);
    if(fd<0) { self.udpError=@"Socket REF indisponible"; return; }
    struct sockaddr_in addr={0}; addr.sin_family=AF_INET;
    addr.sin_port=htons(20810); addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    if(bind(fd,(struct sockaddr *)&addr,sizeof(addr))<0) {
        self.udpError=[NSString stringWithFormat:@"UDP 20810 : %s — fermer le Probe si actif",strerror(errno)];
        close(fd); return;
    }
    if(fcntl(fd,F_SETFL,O_NONBLOCK)<0) { close(fd); self.udpError=@"UDP non bloquant indisponible"; return; }
    self.udpError=nil;
    self.udp=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,fd,0,dispatch_get_main_queue());
    __weak CLSyncMeter *weakSelf=self;
    dispatch_source_set_event_handler(self.udp, ^{
        CLSyncMeter *meter=weakSelf;
        if(!meter) return;
        for(int i=0;i<64;i++) {
            char bytes[512];
            ssize_t n=recv(fd,bytes,sizeof(bytes)-1,0);
            if(n<0) break;
            if(n==0 || n==sizeof(bytes)-1 || memchr(bytes,0,n)) continue;
            bytes[n]=0;
            CLSyncDatagram(&meter->_state,bytes,ClockNow());
        }
    });
    dispatch_source_set_cancel_handler(self.udp, ^{ close(fd); });
    dispatch_resume(self.udp);
}
- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *b=[NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle=NSBezelStyleRounded; return b;
}
- (NSTextField *)audioField {
    NSTextField *f=[NSTextField textFieldWithString:@""];
    f.placeholderString=@"Non renseigné"; f.delegate=self;
    f.font=[NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
    [f.widthAnchor constraintEqualToConstant:130].active=YES;
    return f;
}
- (void)buildWindow {
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1050,760)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"CL Sync Meter"; self.window.minSize=NSMakeSize(820,680);
    self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.backgroundColor=[NSColor colorWithWhite:0.075 alpha:1];
    NSScrollView *scroll=[NSScrollView new]; scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO;
    self.window.contentView=scroll;
    NSView *document=[NSView new]; scroll.documentView=document;
    document.translatesAutoresizingMaskIntoConstraints=NO;
    [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active=YES;
    NSStackView *root=Stack(@[],NSUserInterfaceLayoutOrientationVertical,12);
    root.translatesAutoresizingMaskIntoConstraints=NO; [document addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:document.topAnchor constant:18],
        [root.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-18],
        [root.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-18]]];
    self.lockLabel=Label(@"NO REF",26,NO);
    self.transportLabel=Label(@"25 FPS · Transport —",13,YES);
    NSStackView *heading=Stack(@[Label(@"CL SYNC METER",15,NO),self.lockLabel,self.transportLabel],NSUserInterfaceLayoutOrientationHorizontal,24);
    [root addArrangedSubview:heading];
    self.sourceLabel=Label(@"Initialisation des entrées…",11,NO);
    self.sourceLabel.textColor=NSColor.secondaryLabelColor;
    [root addArrangedSubview:self.sourceLabel];
    self.offsetLabel=Label(@"— ms",58,YES); self.framesLabel=Label(@"— frame",20,YES);
    NSStackView *offset=Stack(@[Label(@"TRANSPORT DELTA · reçu − cible",12,NO),self.offsetLabel,self.framesLabel],NSUserInterfaceLayoutOrientationVertical,4);
    self.refLabel=Label(@"--:--:--:--",20,YES); self.mtcLabel=Label(@"--:--:--:--",20,YES);
    NSStackView *timecodes=Stack(@[Label(@"MTC TARGET · projetée à la réception QF",11,NO),self.refLabel,
        Label(@"MTC RX · +2 frames et phase mesurée",11,NO),self.mtcLabel],NSUserInterfaceLayoutOrientationVertical,5);
    NSStackView *hero=Stack(@[Panel(offset),Panel(timecodes)],NSUserInterfaceLayoutOrientationHorizontal,12);
    self.chainLabel=Label(@"SOURCE / TARGET —",14,YES);
    [root addArrangedSubview:Panel(self.chainLabel)];
    hero.distribution=NSStackViewDistributionFillEqually; [root addArrangedSubview:hero];
    self.timingLabel=Label(@"QF — · REF age — · Samples 0 · Drops 0",12,YES);
    self.statsLabel=Label(@"Moyenne —    Min —    Max —    Jitter —",15,YES);
    NSStackView *stats=Stack(@[self.statsLabel,self.timingLabel,[self button:@"RESET STATS" action:@selector(resetStats:)]],NSUserInterfaceLayoutOrientationVertical,8);
    [root addArrangedSubview:Panel(stats)];
    self.proposalLabel=Label(@"Mesure stable requise",16,YES);
    self.correctionButton=[self button:@"Copier la correction MTC" action:@selector(copyCorrection:)]; self.correctionButton.enabled=NO;
    NSStackView *proposal=Stack(@[Label(@"OFFSET MTC CONSEILLÉ",12,NO),self.proposalLabel,self.correctionButton],NSUserInterfaceLayoutOrientationVertical,6);
    [root addArrangedSubview:Panel(proposal)];
    self.audioMTC=Label(@"—",13,YES);
    self.pdcField=[self audioField]; self.interfaceField=[self audioField]; self.measuredField=[self audioField];
    NSGridView *grid=[NSGridView gridViewWithViews:@[
        @[Label(@"MTC transport · mesure actuelle",12,NO),self.audioMTC,Label(@"ms",11,NO)],
        @[Label(@"Plugins / PDC · estimation manuelle",12,NO),self.pdcField,Label(@"ms",11,NO)],
        @[Label(@"Interface audio · estimation manuelle",12,NO),self.interfaceField,Label(@"ms",11,NO)],
        @[Label(@"Mesure audio externe · saisie manuelle",12,NO),self.measuredField,Label(@"ms",11,NO)]]];
    grid.rowSpacing=6; grid.columnSpacing=14;
    self.audioResult=Label(@"Correction globale —",14,YES);
    NSStackView *audio=Stack(@[Label(@"AUDIO / COMPENSATION",12,NO),grid,self.audioResult,
        Label(@"La valeur audio externe remplace l’estimation totale ; elle n’est jamais additionnée une seconde fois.",10,NO)],NSUserInterfaceLayoutOrientationVertical,7);
    [root addArrangedSubview:Panel(audio)];
    NSTextField *future=Label(@"AUDIO CALIBRATION · À venir : mesure par impulsion / clic sur deux sorties enregistrées sur un même système.",11,NO);
    future.textColor=NSColor.secondaryLabelColor; [root addArrangedSubview:future];
    [root addArrangedSubview:Label(@"Réception uniquement · aucune correction appliquée · statistiques glissantes sur 125 samples",10,NO)];
    for(NSView *view in root.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
}
- (void)resetStats:(id)sender {
    CLSyncBreak(&_state,false); _state.drops=0; [self refreshUI];
}
- (void)copyCorrection:(id)sender {
    CLSyncTick(&_state,ClockNow());
    if(!CLSyncCanRecommend(&_state)) return;
    NSString *value=[NSString stringWithFormat:@"%+.2f ms",-CLSyncStatistics(&_state).mean];
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:value forType:NSPasteboardTypeString];
}
- (double)manualValue:(NSTextField *)field {
    NSString *s=[[field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"," withString:@"."];
    if(!s.length) return NAN;
    const char *start=s.UTF8String; char *end=NULL;
    double value=strtod(start,&end);
    return end!=start && *end==0 && isfinite(value) && value>=0 && value<=10000?value:NAN;
}
- (void)controlTextDidChange:(NSNotification *)notification { [self refreshUI]; }
- (void)refreshUI {
    double now=ClockNow(); CLSyncTick(&_state,now);
    BOOL valid=_state.locked && _state.count;
    BOOL recommend=CLSyncCanRecommend(&_state);
    CLSyncStats stats=CLSyncStatistics(&_state);
    self.lockLabel.stringValue=[NSString stringWithUTF8String:CLSyncStatus(&_state)];
    self.lockLabel.textColor=(valid && _state.absFresh)?NSColor.systemGreenColor:(_state.hasRef&&!_state.running)?NSColor.secondaryLabelColor:NSColor.systemOrangeColor;
    if(self.udpError || self.midiError) self.lockLabel.textColor=NSColor.systemRedColor;
    self.transportLabel.stringValue=[NSString stringWithFormat:@"25 FPS · %@",_state.hasRef?(_state.running?@"PLAY":@"STOP"):@"Transport —"];
    self.sourceLabel.stringValue=[NSString stringWithFormat:@"MTC : %@%@\nREF : UDP localhost:20810%@ · %@",
        (_source?MIDIName(_source):MTCSourceName),self.midiError?[@" · " stringByAppendingString:self.midiError]:@" · disponible",
        self.udpError?[@" · " stringByAppendingString:self.udpError]:@" · écoute",NSProcessInfo.processInfo.hostName];
    self.chainLabel.stringValue=_state.hasRef?[NSString stringWithFormat:
        @"SOURCE ABS  %@  %@\n↓ BRIDGE  %@  %@  + OFFSET CONFIGURÉ  %+.2f ms\n↓ MTC TARGET  %.3f s  → CoreMIDI → MTC RX\nInstance %llx · Séquence %llu",
        _state.hasABS?Timecode(_state.absRaw):@"—",_state.absFresh?@"FRESH":@"STALE",
        Timecode(_state.bridgeSeconds),_state.absFresh?@"ABS LOCK":@"FREE-RUN",
        _state.bridgeOffset,_state.refSeconds,(unsigned long long)_state.instance,(unsigned long long)_state.sequence]:@"SOURCE / TARGET — OFFLINE";
    self.chainLabel.textColor=_state.hasRef&&_state.absFresh?NSColor.labelColor:NSColor.secondaryLabelColor;
    self.refLabel.textColor=_state.hasRef?NSColor.labelColor:NSColor.secondaryLabelColor;
    self.mtcLabel.textColor=_state.hasMTC&&_state.hasRef?NSColor.labelColor:NSColor.secondaryLabelColor;
    self.offsetLabel.stringValue=valid?[NSString stringWithFormat:@"%+.2f ms",_state.deltaMs]:@"— ms";
    self.framesLabel.stringValue=valid?[NSString stringWithFormat:@"%+.3f frame",_state.deltaMs/40]:@"— frame";
    self.refLabel.stringValue=_state.hasRef?[NSString stringWithFormat:@"%@ · %.3f s",Timecode(valid?_state.measuredRef:_state.refSeconds),valid?_state.measuredRef:_state.refSeconds]:@"--:--:--:--";
    self.mtcLabel.stringValue=valid?[NSString stringWithFormat:@"%@ · %.3f s",Timecode(_state.mtcSeconds),_state.mtcSeconds]:@"--:--:--:--";
    self.statsLabel.stringValue=valid?[NSString stringWithFormat:@"AVG %+.2f   MIN %+.2f   MAX %+.2f   JITTER %.2f ms",stats.mean,stats.min,stats.max,stats.jitter]:@"AVG —   MIN —   MAX —   JITTER —";
    NSString *cycle=_state.cycleMs>0?[NSString stringWithFormat:@"%.1f ms",_state.cycleMs]:@"—";
    NSString *age=_state.hasRef?[NSString stringWithFormat:@"%.0f ms",fmax(0,now-_state.refArrival)*1000]:@"—";
    self.timingLabel.stringValue=[NSString stringWithFormat:@"QF %@ · REF age %@ · Samples %llu · Drops session %llu · Lock %.1f s",cycle,age,(unsigned long long)_state.samples,(unsigned long long)_state.drops,valid?fmax(0,now-_state.lockSince):0];
    self.proposalLabel.stringValue=recommend?[NSString stringWithFormat:@"Moyenne %+.2f ms → correction %+.2f ms",stats.mean,-stats.mean]:@"ACQUIRING · mesure insuffisante (25 samples, jitter ≤2 ms)";
    self.correctionButton.enabled=recommend;
    self.audioMTC.stringValue=valid?[NSString stringWithFormat:@"%+.2f",stats.mean]:@"—";
    double pdc=[self manualValue:self.pdcField], interface=[self manualValue:self.interfaceField], measured=[self manualValue:self.measuredField];
    if(isfinite(measured)) self.audioResult.stringValue=[NSString stringWithFormat:@"Correction globale %+.2f ms · d’après la saisie audio externe",-measured];
    else if(self.measuredField.stringValue.length) self.audioResult.stringValue=@"Saisie audio invalide · valeur attendue de 0 à 10 000 ms";
    else if(valid && isfinite(pdc) && isfinite(interface)) self.audioResult.stringValue=[NSString stringWithFormat:@"Correction globale estimée %+.2f ms · MTC + PDC + interface",-(stats.mean+pdc+interface)];
    else self.audioResult.stringValue=@"Correction globale — · renseigner les latences ou la mesure externe";
}
- (void)startReceivers {
    [self discoverSource]; [self listenUDP];
    __weak CLSyncMeter *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        CLSyncMeter *meter=weakSelf; if(!meter) return;
        if(ClockNow()-meter->_lastDiscovery>1) {
            meter->_lastDiscovery=ClockNow(); [meter discoverSource]; [meter listenUDP];
        }
        if(meter.diagnose) CLSyncTick(&meter->_state,ClockNow()); else [meter refreshUI];
    }];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildWindow]; [self startReceivers]; [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)stopReceivers {
    [self.timer invalidate]; self.timer=nil;
    if(self.udp) { dispatch_source_cancel(self.udp); self.udp=nil; }
    if(_port) { MIDIPortDispose(_port); _port=0; }
    if(_client) { MIDIClientDispose(_client); _client=0; }
}
- (void)applicationWillTerminate:(NSNotification *)notification { [self stopReceivers]; }
- (void)diagnosticReport {
    NSDictionary *report=@{@"mtc_source":(_source?MIDIName(_source):MTCSourceName),@"source_available":@(_source!=0),
        @"udp_listening":@(self.udp!=nil),@"reference_received":@(_state.hasRef),
        @"state":[NSString stringWithUTF8String:CLSyncStatus(&_state)],@"samples":@(_state.samples),
        @"drops":@(_state.drops),@"midi_error":self.midiError?:@"",@"udp_error":self.udpError?:@""};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
    puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}
@end

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        CLSyncMeter *delegate=[CLSyncMeter new];
        if(argc>1 && strcmp(argv[1],"--diagnose")==0) {
            delegate.diagnose=YES; [delegate startReceivers];
            NSDate *end=[NSDate dateWithTimeIntervalSinceNow:3];
            while(end.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
            [delegate diagnosticReport]; [delegate stopReceivers]; return 0;
        }
        NSApplication *app=NSApplication.sharedApplication;
        app.activationPolicy=NSApplicationActivationPolicyRegular; app.delegate=delegate;
        NSMenu *menu=[NSMenu new],*application=[NSMenu new];
        NSMenuItem *item=[NSMenuItem new]; [menu addItem:item]; item.submenu=application;
        [application addItemWithTitle:@"Quitter CL Sync Meter" action:@selector(terminate:) keyEquivalent:@"q"];
        app.mainMenu=menu; [app run];
    }
    return 0;
}
