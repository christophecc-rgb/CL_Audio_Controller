#import "CLMIDICore.h"
#import "CLMIDILogger.h"

@interface CLMIDICore ()
{
    MIDIClientRef _client;
    MIDIPortRef _inputPort;
    CLMIDILogger *_logger;
    NSMutableSet<NSNumber *> *_connectedSourceIDs;
}

- (void)connectAvailableSources;
- (void)receivedPacketList:(const MIDIPacketList *)packetList
                 fromSource:(MIDIEndpointRef)source;
@end

static void CLMIDIReadProc(const MIDIPacketList *packetList,
                           void *readProcRefCon,
                           void *srcConnRefCon)
{
    @autoreleasepool
    {
        CLMIDICore *core = (__bridge CLMIDICore *)readProcRefCon;
        MIDIEndpointRef source = (MIDIEndpointRef)(uintptr_t)srcConnRefCon;
        [core receivedPacketList:packetList fromSource:source];
    }
}

static void CLMIDINotifyProc(const MIDINotification *message, void *refCon)
{
    if (message->messageID != kMIDIMsgObjectAdded &&
        message->messageID != kMIDIMsgSetupChanged)
    {
        return;
    }

    @autoreleasepool
    {
        CLMIDICore *core = (__bridge CLMIDICore *)refCon;
        [core connectAvailableSources];
    }
}

@implementation CLMIDICore

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _logger = [CLMIDILogger new];
        _connectedSourceIDs = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc
{
    [self stopMonitoring];
}

- (void)scanPorts
{
    NSLog(@"========== CORE MIDI ==========");
    ItemCount sources = MIDIGetNumberOfSources();
    NSLog(@"Sources : %lu", (unsigned long)sources);
    for (ItemCount index = 0; index < sources; index++)
    {
        [self printEndpoint:MIDIGetSource(index) index:index];
    }

    NSLog(@"");
    ItemCount destinations = MIDIGetNumberOfDestinations();
    NSLog(@"Destinations : %lu", (unsigned long)destinations);
    for (ItemCount index = 0; index < destinations; index++)
    {
        [self printEndpoint:MIDIGetDestination(index) index:index];
    }
}

- (BOOL)startMonitoring
{
    if (_client != 0)
    {
        return YES;
    }

    NSLog(@"");
    NSLog(@"Creating MIDI Client...");
    OSStatus status = MIDIClientCreate(CFSTR("CL Audio Analyzer"),
                                       CLMIDINotifyProc,
                                       (__bridge void *)self,
                                       &_client);
    if (status != noErr)
    {
        NSLog(@"MIDIClientCreate failed: %d", (int)status);
        return NO;
    }

    NSLog(@"Client created.");
    status = MIDIInputPortCreate(_client,
                                 CFSTR("CL Audio Input"),
                                 CLMIDIReadProc,
                                 (__bridge void *)self,
                                 &_inputPort);
    if (status != noErr)
    {
        NSLog(@"Unable to create input port: %d", (int)status);
        MIDIClientDispose(_client);
        _client = 0;
        return NO;
    }

    NSLog(@"Input port created.");
    [self connectAvailableSources];
    NSLog(@"Monitoring MIDI. Press Control-C to stop.");
    return YES;
}

- (void)stopMonitoring
{
    if (_inputPort != 0)
    {
        MIDIPortDispose(_inputPort);
        _inputPort = 0;
    }
    if (_client != 0)
    {
        MIDIClientDispose(_client);
        _client = 0;
    }
    [_connectedSourceIDs removeAllObjects];
}

- (void)connectAvailableSources
{
    if (_inputPort == 0)
    {
        return;
    }

    ItemCount sourceCount = MIDIGetNumberOfSources();
    for (ItemCount index = 0; index < sourceCount; index++)
    {
        MIDIEndpointRef source = MIDIGetSource(index);
        if (source == 0)
        {
            continue;
        }

        MIDIUniqueID uniqueID = 0;
        OSStatus propertyStatus = MIDIObjectGetIntegerProperty(source,
                                                               kMIDIPropertyUniqueID,
                                                               &uniqueID);
        NSNumber *sourceKey = propertyStatus == noErr
            ? @(uniqueID)
            : @((uintptr_t)source);
        if ([_connectedSourceIDs containsObject:sourceKey])
        {
            continue;
        }

        OSStatus status = MIDIPortConnectSource(_inputPort,
                                                source,
                                                (void *)(uintptr_t)source);
        if (status == noErr)
        {
            [_connectedSourceIDs addObject:sourceKey];
            NSLog(@"Connected source [%lu]: %@",
                  (unsigned long)index,
                  [self nameForEndpoint:source]);
        }
        else
        {
            NSLog(@"Unable to connect source [%lu] (%d)",
                  (unsigned long)index,
                  (int)status);
        }
    }
}

- (void)receivedPacketList:(const MIDIPacketList *)packetList
                 fromSource:(MIDIEndpointRef)source
{
    [_logger logPacketList:packetList fromSource:source];
}

- (NSString *)nameForEndpoint:(MIDIEndpointRef)endpoint
{
    CFStringRef name = NULL;
    OSStatus status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name);
    if (status != noErr || name == NULL)
    {
        status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name);
    }
    if (status != noErr || name == NULL)
    {
        return @"<unknown>";
    }
    return CFBridgingRelease(name);
}

- (void)printEndpoint:(MIDIEndpointRef)endpoint index:(NSUInteger)index
{
    NSLog(@"[%lu] %@", (unsigned long)index, [self nameForEndpoint:endpoint]);
}

@end
