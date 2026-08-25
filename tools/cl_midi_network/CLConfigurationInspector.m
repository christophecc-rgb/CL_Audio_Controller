#import "CLConfigurationChecker.h"
#import <CoreMIDI/CoreMIDI.h>
#import <libproc.h>

static NSString *CLMIDIStringProperty(MIDIObjectRef object, CFStringRef property) {
    CFStringRef value = NULL;
    if (MIDIObjectGetStringProperty(object, property, &value) != noErr || !value) return @"";
    return CFBridgingRelease(value);
}

static NSNumber *CLMIDIIntegerProperty(MIDIObjectRef object, CFStringRef property) {
    SInt32 value = 0;
    return MIDIObjectGetIntegerProperty(object, property, &value) == noErr ? @(value) : @0;
}

static NSString *CLMidiClass(NSString *name, id driverOwner) {
    NSString *text = [NSString stringWithFormat:@"%@ %@", name ?: @"", driverOwner ?: @""];
    if ([text rangeOfString:@"network" options:NSCaseInsensitiveSearch].location != NSNotFound || [text rangeOfString:@"réseau" options:NSCaseInsensitiveSearch].location != NSNotFound || [text rangeOfString:@"rtp" options:NSCaseInsensitiveSearch].location != NSNotFound) return @"rtp";
    if ([text rangeOfString:@"IAC" options:NSCaseInsensitiveSearch].location != NSNotFound) return @"iac";
    if ([text rangeOfString:@"CL MIDI" options:NSCaseInsensitiveSearch].location != NSNotFound) return @"cl_audio_virtual";
    return @"other";
}

static NSArray *CLMidiEndpoints(void) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger direction = 0; direction < 2; direction++) {
        ItemCount count = direction ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources();
        for (ItemCount index = 0; index < count; index++) {
            MIDIEndpointRef endpoint = direction ? MIDIGetDestination(index) : MIDIGetSource(index);
            NSString *name = CLMIDIStringProperty(endpoint, kMIDIPropertyDisplayName);
            if (!name.length) name = CLMIDIStringProperty(endpoint, kMIDIPropertyName);
            id owner = CLMIDIStringProperty(endpoint, kMIDIPropertyDriverOwner);
            [result addObject:@{
                @"name": name ?: @"", @"direction": direction ? @"destination" : @"source",
                @"unique_id": CLMIDIIntegerProperty(endpoint, kMIDIPropertyUniqueID),
                @"device": CLMIDIIntegerProperty(endpoint, kMIDIPropertyDeviceID),
                @"entity": CLMIDIStringProperty(endpoint, kMIDIPropertyName),
                @"manufacturer": CLMIDIStringProperty(endpoint, kMIDIPropertyManufacturer),
                @"model": CLMIDIStringProperty(endpoint, kMIDIPropertyModel),
                @"driver_owner": owner ?: @"", @"classification": CLMidiClass(name, owner),
            }];
        }
    }
    return result;
}

static NSString *CLRun(NSString *path, NSArray *arguments) {
    NSTask *task = [NSTask new]; task.executableURL = [NSURL fileURLWithPath:path]; task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe]; task.standardOutput = pipe; task.standardError = NSFileHandle.fileHandleWithNullDevice;
    if (![task launchAndReturnError:nil]) return @"";
    NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

static NSArray *CLProcesses(void) {
    NSString *output = CLRun(@"/bin/ps", @[@"-axo", @"pid=,command="]);
    NSArray *needles = @[@"CL Audio Show Control", @"CL Audio Controller", @"CL MIDI Network Assistant", @"CL MIDI RTP Agent", @"CLMIDINetworkGuardian", @"CLYamahaConsoleSimulator", @"app.py", @"Ableton Live"];
    NSMutableArray *items = [NSMutableArray array];
    [output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        (void)stop;
        BOOL relevant = NO; for (NSString *needle in needles) if ([line containsString:needle]) { relevant = YES; break; }
        if (!relevant) return;
        NSScanner *scanner = [NSScanner scannerWithString:line]; NSInteger pid = 0; [scanner scanInteger:&pid];
        NSString *command = [[line substringFromIndex:scanner.scanLocation] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        char buffer[PROC_PIDPATHINFO_MAXSIZE] = {0}; int length = proc_pidpath((int)pid, buffer, sizeof(buffer));
        NSString *path = length > 0 ? [NSString stringWithUTF8String:buffer] : @"";
        NSString *location = path.length ? path : command;
        [items addObject:@{@"pid": @(pid), @"path": path, @"command": command, @"app_translocation": @([location containsString:@"/AppTranslocation/"]), @"development_build": @([location containsString:@"/Documents/Codex/"] || [location containsString:@"/work/"] || [location containsString:@"/dist/"])}];
    }];
    return items;
}

static NSDictionary *CLPorts(void) {
    NSMutableDictionary *ports = [NSMutableDictionary dictionary];
    for (NSNumber *port in @[@5050, @11000, @11001, @63123]) {
        NSString *output = CLRun(@"/usr/sbin/lsof", @[@"-nP", [NSString stringWithFormat:@"-i:%@", port], @"-sTCP:LISTEN"]);
        if (!output.length) output = CLRun(@"/usr/sbin/lsof", @[@"-nP", [NSString stringWithFormat:@"-iUDP:%@", port]]);
        NSMutableArray *lines = [[output componentsSeparatedByString:@"\n"] mutableCopy]; if (lines.count) [lines removeObjectAtIndex:0];
        NSIndexSet *empty = [lines indexesOfObjectsPassingTest:^BOOL(NSString *line, NSUInteger idx, BOOL *stop) { (void)idx; (void)stop; return !line.length; }]; [lines removeObjectsAtIndexes:empty];
        ports[port.stringValue] = lines;
    }
    return ports;
}

static NSDictionary *CLServerStatus(void) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:5050/status"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:1.0];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0); __block NSDictionary *payload = @{};
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        (void)response; if (!error && data.length) { id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; if ([value isKindOfClass:NSDictionary.class]) payload = value; } dispatch_semaphore_signal(semaphore);
    }] resume];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)));
    return payload;
}

@implementation CLConfigurationInspector
- (NSDictionary *)inspect {
    MIDIClientRef client = 0; MIDIClientCreate(CFSTR("CL Configuration Checker"), NULL, NULL, &client);
    MIDINetworkSession *session = MIDINetworkSession.defaultSession;
    NSMutableArray *connections = [NSMutableArray array];
    for (MIDINetworkConnection *connection in session.connections) [connections addObject:connection.host.netServiceName ?: connection.host.name ?: connection.host.address ?: @""];
    NSDictionary *result = @{
        @"captured_at": @([NSDate.date timeIntervalSince1970]), @"hostname": NSHost.currentHost.localizedName ?: @"",
        @"midi_endpoints": CLMidiEndpoints(),
        @"rtp": @{@"local_session_name": session.localName ?: @"", @"bonjour_name": session.networkName ?: @"", @"port": @(session.networkPort), @"enabled": @(session.isEnabled), @"connections": connections},
        @"processes": CLProcesses(), @"ports": CLPorts(), @"server_status": CLServerStatus(),
    };
    if (client) MIDIClientDispose(client); return result;
}
@end
