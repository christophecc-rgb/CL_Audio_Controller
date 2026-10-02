#import "../../tools/shared/CLMIDIEndpointNames.h"
#include <assert.h>
int main(int argc, const char **argv) { @autoreleasepool {
    NSDictionary *table=CLMIDINameTable();
    if(argc>1 && !strcmp(argv[1],"--table")) {
        NSData *json=[NSJSONSerialization dataWithJSONObject:table options:0 error:nil];
        puts([[NSString alloc]initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        return 0;
    }
    for(NSString *canonical in table) {
        NSArray *aliases=table[canonical];
        assert([CLMIDIResolveName(@[canonical],canonical) isEqualToString:canonical]);
        assert(CLMIDIResolveName(@[],canonical)==nil);
        for(NSString *alias in aliases) {
            assert([CLMIDIResolveName(@[alias],canonical) isEqualToString:alias]);
            assert([CLMIDIResolveName(@[alias,canonical],canonical) isEqualToString:canonical]);
            assert([CLMIDIResolveName(@[alias,canonical],alias) isEqualToString:canonical]);
            assert(CLMIDINameMatches(alias,canonical));
        }
        for(NSString *other in table) if(![other isEqualToString:canonical])
            assert(!CLMIDINameMatches(other,canonical));
    }
    assert([CLMIDIResolveName(@[@"Gestionnaire IAC MTC vers Logic",@"Gestionnaire IAC CL MTC IAC"],@CL_MIDI_MTC_IAC) isEqualToString:@"Gestionnaire IAC CL MTC IAC"]);
    assert(CLMIDIResolveName(@[@"Réseau CL MTC"],@CL_MIDI_MTC_IAC)==nil);
    assert(CLMIDIResolveName(@[@"Réseau CL Ableton Clock"],@CL_MIDI_CLOCK_IAC)==nil);
    assert(CLMIDINameMatches(@"Réseau Rtp MB Chris",@CL_MIDI_RETURN_RTP));
    puts("MIDI endpoint names: OK");
} return 0; }
