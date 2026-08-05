#import "CLMIDICore.h"
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

@interface CLMIDICore ()
{
    MIDIClientRef _client;
    MIDIPortRef _inputPort;
}
@end

@implementation CLMIDICore

- (instancetype)init
{
    self = [super init];

    if (self)
    {
        _client = 0;
        _inputPort = 0;
    }

    return self;
}

- (void)dealloc
{
    if (_inputPort)
    {
        MIDIPortDispose(_inputPort);
    } if (_client)
    {
        MIDIClientDispose(_client);
    }
}

- (void)scanPorts
{
    NSLog(@"========== CORE MIDI ==========");

    ItemCount sources = MIDIGetNumberOfSources();

    NSLog(@"Sources : %lu",(unsigned long)sources);

    for(ItemCount i=0;i<sources;i++)
    {
        [self printEndpoint:MIDIGetSource(i) index:i];
    }

    NSLog(@"");

    ItemCount destinations=MIDIGetNumberOfDestinations();

    NSLog(@"Destinations : %lu",(unsigned long)destinations);

    for(ItemCount i=0;i<destinations;i++)
    {
        [self printEndpoint:MIDIGetDestination(i) index:i];
    }
}

- (void)startMonitoring
{
    NSLog(@"");
    NSLog(@"Creating MIDI Client...");


    OSStatus err =
    MIDIClientCreate(
     CFSTR("CL Audio Analyzer"),
        NULL,
        NULL,
        &_client);

    if(err!=noErr)
    {
        NSLog(@"MIDIClientCreate failed : %d",(int)err);
        return;
    }

    NSLog(@"Client created.");

    OSStatus status =
MIDIInputPortCreate(
    _client,
    CFSTR("CL Audio Input"),
    NULL,
    NULL,
    &_inputPort);

    if (status != noErr)
    {
    NSLog(@"Unable to create input port (%d)", (int)status);
    return;
}

    NSLog(@"Input port created.");
    
    NSLog(@"Ready for source connection.");
}

- (void)printEndpoint:(MIDIEndpointRef)endpoint
                index:(NSUInteger)index
{
    CFStringRef name=NULL;

    MIDIObjectGetStringProperty(
        endpoint,
        kMIDIPropertyName,
        &name);

    NSString *text=@"<unknown>";

    if(name)
    {
        text=[(__bridge NSString*)name copy];
        CFRelease(name);
    }

    NSLog(@"[%lu] %@",
          (unsigned long)index,
          text);
}

@end
