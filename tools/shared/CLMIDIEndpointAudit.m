/* Read-only: no connections, no packets, no property writes. */
#import "CLMIDIEndpointNames.h"
int main(void) { @autoreleasepool {
    MIDIClientRef client=0;
    OSStatus status=MIDIClientCreate(CFSTR("CL Endpoint Naming Audit"),NULL,NULL,&client);
    if(status) { fprintf(stderr,"CoreMIDI indisponible: %d\n",(int)status); return 1; }
    NSMutableArray *rows=[NSMutableArray array];
    for(NSString *role in [[CLMIDINameTable() allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        for(NSNumber *source in @[@YES,@NO]) {
            MIDIEndpointRef ep=CLMIDIFindEndpoint(source.boolValue,role);
            SInt32 uid=0; if(ep)MIDIObjectGetIntegerProperty(ep,kMIDIPropertyUniqueID,&uid);
            [rows addObject:@{@"canonical":role,@"direction":source.boolValue?@"source":@"destination",@"actual":ep?CLMIDIEndpointDisplayName(ep):@"ABSENT",@"uid":@(uid)}];
        }
    }
    NSData *json=[NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:nil];
    puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
    MIDIClientDispose(client);
} return 0; }
