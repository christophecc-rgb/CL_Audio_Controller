#import "CLMIDICore.h"
#import "CLCommand.h"
#import "CLMIDIEvent.h"
#import "CLMIDICommandInterpreter.h"
#import "CLMIDILogger.h"
#import "CLMIDIPacket.h"
#import "CLMIDIPort.h"

@interface CLMIDICore () <CLMIDIPortDelegate>
{
    MIDIClientRef _client;
    CLMIDIPort *_inputPort;
    CLMIDILogger *_logger;
    id<CLMIDIEventCommandInterpreting> _commandInterpreter;
}

- (void)refreshSources;
@end


static void CLMIDINotifyProc(const MIDINotification *message, void *refCon)
{
    if (message->messageID != kMIDIMsgObjectAdded &&
        message->messageID != kMIDIMsgObjectRemoved &&
        message->messageID != kMIDIMsgSetupChanged)
    {
        return;
    }

    @autoreleasepool
    {
        CLMIDICore *core = (__bridge CLMIDICore *)refCon;
        [core refreshSources];
    }
}

@implementation CLMIDICore

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _logger = [CLMIDILogger new];
        _commandInterpreter = [CLMIDICommandInterpreter new];
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

    OSStatus status = MIDIClientCreate(CFSTR("CL Audio Analyzer"),
                                       CLMIDINotifyProc,
                                       (__bridge void *)self,
                                       &_client);
    if (status != noErr)
    {
        NSLog(@"MIDIClientCreate failed: %d", (int)status);
        return NO;
    }

    _inputPort = [[CLMIDIPort alloc] initWithClient:_client delegate:self];
    NSError *error = nil;
    if (![_inputPort open:&error])
    {
        NSLog(@"%@", error.localizedDescription);
        _inputPort = nil;
        MIDIClientDispose(_client);
        _client = 0;
        return NO;
    }

    NSLog(@"");
    NSLog(@"Listening...");
    return YES;
}

- (void)stopMonitoring
{
    [_inputPort close];
    _inputPort = nil;
    if (_client != 0)
    {
        MIDIClientDispose(_client);
        _client = 0;
    }
}

- (void)refreshSources
{
    [_inputPort refreshSources];
}

- (void)midiPort:(CLMIDIPort *)port didReceivePacket:(CLMIDIPacket *)packet
{
    (void)port;
    CLMIDIEvent *event = [[CLMIDIEvent alloc] initWithPacket:packet];
    [_logger logEvent:event];
    for (CLCommand *command in [_commandInterpreter commandsForEvent:event])
    {
        id<CLCommandReceiver> receiver = self.commandReceiver;
        if ([receiver conformsToProtocol:@protocol(CLCommandTraceReceiver)])
        {
            [(id<CLCommandTraceReceiver>)receiver receiveCommand:command originatingEvent:event];
        }
        else
        {
            [self.commandReceiver receiveCommand:command];
        }
    }
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
