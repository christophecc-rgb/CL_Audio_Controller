#define main clDashboardMain
#import "../../tools/cl_midi_network/CLMIDINetworkDashboard.m"
#undef main
#include <assert.h>
int main(void) { @autoreleasepool {
    for (NSString *name in CLMIDICandidates(@CL_MIDI_SHOW_IAC)) {
        assert(!CLIsRTPReturnEndpointName(name));
        assert(CLIsProtectedDeviceTestEndpoint(name));
    }
    for (NSString *name in CLMIDICandidates(@CL_MIDI_SHOW_RTP))
        assert(!CLIsRTPReturnEndpointName(name));
    assert(!CLIsRTPReturnEndpointName(@CL_MIDI_DIRECT_RTP));
    assert(!CLIsRTPReturnEndpointName(@CL_MIDI_RETURN_TEST));
    for (NSString *name in CLMIDICandidates(@CL_MIDI_RETURN_RTP))
        assert(CLIsRTPReturnEndpointName(name));
    assert([CLLocalReturnSourceName(@[@"Gestionnaire IAC CL MIDI Return Test"]) isEqual:@"Gestionnaire IAC CL MIDI Return Test"]);
    assert([CLLocalReturnSourceName(@[@"CL MIDI Return Test"]) isEqual:@"CL MIDI Return Test"]);
    assert([CLLocalReturnSourceName(@[@"IAC Driver CL MIDI Return Test"]) isEqual:@"IAC Driver CL MIDI Return Test"]);
    assert([CLLocalReturnSourceName(@[@"Gestionnaire IAC CL MIDI Return Test", @"CL MIDI Return Test"]) isEqual:@"CL MIDI Return Test"]);
    assert(CLLocalReturnSourceName(@[@"Gestionnaire IAC Bus 1", @"Réseau CL MIDI Return Test"]) == nil);
    puts("Dashboard endpoint roles: OK");
} return 0; }
