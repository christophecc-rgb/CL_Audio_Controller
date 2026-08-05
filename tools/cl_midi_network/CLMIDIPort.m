#import "CLMIDIPort.h"
#import "CLMIDIPacket.h"

static NSString * const CLMIDIPortErrorDomain = @"com.claudio.midi.port";

@interface CLMIDISourceConnection : NSObject
@property (nonatomic) MIDIEndpointRef endpoint;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSNumber *identifier;
@property (nonatomic) void *callbackContext;
@end

@implementation CLMIDISourceConnection
@end


@interface CLMIDIPort ()
{
    MIDIClientRef _client;
    MIDIPortRef _inputPort;
    NSMutableDictionary<NSNumber *, CLMIDISourceConnection *> *_connections;
}

- (void)receivePacketList:(const MIDIPacketList *)packetList
               connection:(CLMIDISourceConnection *)connection;
@end


static void CLMIDIPortReadProc(const MIDIPacketList *packetList,
                               void *readProcRefCon,
                               void *srcConnRefCon)
{
    @autoreleasepool
    {
        CLMIDIPort *port = (__bridge CLMIDIPort *)readProcRefCon;
        CLMIDISourceConnection *connection = (__bridge CLMIDISourceConnection *)srcConnRefCon;
        [port receivePacketList:packetList connection:connection];
    }
}

@implementation CLMIDIPort

- (instancetype)initWithClient:(MIDIClientRef)client
                       delegate:(id<CLMIDIPortDelegate>)delegate
{
    self = [super init];
    if (self)
    {
        _client = client;
        _delegate = delegate;
        _connections = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (BOOL)open:(NSError **)error
{
    if (_inputPort != 0)
    {
        return YES;
    }

    OSStatus status = MIDIInputPortCreate(_client,
                                          CFSTR("CL Audio Input"),
                                          CLMIDIPortReadProc,
                                          (__bridge void *)self,
                                          &_inputPort);
    if (status != noErr)
    {
        if (error != NULL)
        {
            *error = [NSError errorWithDomain:CLMIDIPortErrorDomain
                                         code:status
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Unable to create MIDI input port (%d)",
                                                                    (int)status]}];
        }
        return NO;
    }

    [self refreshSources];
    return YES;
}

- (void)refreshSources
{
    @synchronized (self)
    {
        [self refreshSourcesLocked];
    }
}

- (void)refreshSourcesLocked
{
    if (_inputPort == 0)
    {
        return;
    }

    NSMutableSet<NSNumber *> *availableIdentifiers = [NSMutableSet set];
    ItemCount sourceCount = MIDIGetNumberOfSources();
    for (ItemCount index = 0; index < sourceCount; index++)
    {
        MIDIEndpointRef source = MIDIGetSource(index);
        if (source == 0)
        {
            continue;
        }

        NSNumber *identifier = [self identifierForSource:source];
        [availableIdentifiers addObject:identifier];

        CLMIDISourceConnection *existing = _connections[identifier];
        if (existing != nil && existing.endpoint == source)
        {
            continue;
        }
        if (existing != nil)
        {
            [self disconnectConnection:existing];
            [_connections removeObjectForKey:identifier];
        }

        CLMIDISourceConnection *connection = [CLMIDISourceConnection new];
        connection.endpoint = source;
        connection.name = [self nameForSource:source];
        connection.identifier = identifier;

        connection.callbackContext = (__bridge_retained void *)connection;
        OSStatus status = MIDIPortConnectSource(_inputPort,
                                                source,
                                                connection.callbackContext);
        if (status == noErr)
        {
            _connections[identifier] = connection;
            NSLog(@"Connected source : %@", connection.name);
        }
        else
        {
            CFBridgingRelease(connection.callbackContext);
            connection.callbackContext = NULL;
            NSLog(@"Unable to connect source %@ (%d)", connection.name, (int)status);
        }
    }

    NSArray<NSNumber *> *knownIdentifiers = _connections.allKeys.copy;
    for (NSNumber *identifier in knownIdentifiers)
    {
        if (![availableIdentifiers containsObject:identifier])
        {
            CLMIDISourceConnection *connection = _connections[identifier];
            [self disconnectConnection:connection];
            [_connections removeObjectForKey:identifier];
        }
    }
}

- (void)close
{
    @synchronized (self)
    {
        if (_inputPort == 0)
        {
            return;
        }

        for (CLMIDISourceConnection *connection in _connections.allValues)
        {
            [self disconnectConnection:connection];
        }
        [_connections removeAllObjects];
        MIDIPortDispose(_inputPort);
        _inputPort = 0;
    }
}

- (void)disconnectConnection:(CLMIDISourceConnection *)connection
{
    MIDIPortDisconnectSource(_inputPort, connection.endpoint);
    if (connection.callbackContext != NULL)
    {
        CFBridgingRelease(connection.callbackContext);
        connection.callbackContext = NULL;
    }
}

- (void)receivePacketList:(const MIDIPacketList *)packetList
               connection:(CLMIDISourceConnection *)connection
{
    if (packetList == NULL || connection == nil)
    {
        return;
    }

    const MIDIPacket *packet = &packetList->packet[0];
    for (UInt32 index = 0; index < packetList->numPackets; index++)
    {
        CLMIDIPacket *receivedPacket = [[CLMIDIPacket alloc]
            initWithBytes:packet->data
                   length:packet->length
                timestamp:packet->timeStamp
               sourceName:connection.name];
        [self.delegate midiPort:self didReceivePacket:receivedPacket];
        packet = MIDIPacketNext(packet);
    }
}

- (NSNumber *)identifierForSource:(MIDIEndpointRef)source
{
    MIDIUniqueID uniqueID = 0;
    OSStatus status = MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &uniqueID);
    return status == noErr && uniqueID != 0 ? @(uniqueID) : @((uintptr_t)source);
}

- (NSString *)nameForSource:(MIDIEndpointRef)source
{
    CFStringRef name = NULL;
    OSStatus status = MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name);
    if (status != noErr || name == NULL)
    {
        status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name);
    }
    if (status != noErr || name == NULL)
    {
        return @"<unknown>";
    }
    return CFBridgingRelease(name);
}

@end
