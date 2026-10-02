#ifndef CL_MIDI_ENDPOINT_NAMES_H
#define CL_MIDI_ENDPOINT_NAMES_H
#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>
#define CL_MIDI_CLOCK_IAC "CL Ableton Clock IAC"
#define CL_MIDI_MTC_IAC "CL MTC IAC"
#define CL_MIDI_SHOW_IAC "CL Show Control IAC"
#define CL_MIDI_SHOW_RTP "CL Show Control RTP"
#define CL_MIDI_RETURN_RTP "CL Console Return RTP"
#define CL_MIDI_RETURN_TEST "CL MIDI Return Test"
#define CL_MIDI_DIRECT_RTP "CL Direct RTP"

/* Display-name aliases only. Never interpret these as peer/Bonjour names. */
static inline NSDictionary<NSString *, NSArray<NSString *> *> *CLMIDINameTable(void) {
    static NSDictionary *table; static dispatch_once_t once;
    dispatch_once(&once, ^{ table = @{
        @CL_MIDI_CLOCK_IAC: @[@"Gestionnaire IAC CL Ableton Clock IAC", @"IAC Driver CL Ableton Clock IAC", @"Gestionnaire IAC Ableton Clock", @"IAC Driver Ableton Clock"],
        @CL_MIDI_MTC_IAC: @[@"Gestionnaire IAC CL MTC IAC", @"IAC Driver CL MTC IAC", @"Gestionnaire IAC MTC vers Logic", @"IAC Driver MTC vers Logic"],
        @CL_MIDI_SHOW_IAC: @[@"Gestionnaire IAC CL Show Control IAC", @"IAC Driver CL Show Control IAC", @"Gestionnaire IAC Bus 1", @"IAC Driver Bus 1"],
        @CL_MIDI_SHOW_RTP: @[@"Réseau CL Show Control RTP", @"Network CL Show Control RTP", @"Réseau CL Show Control", @"Network CL Show Control"],
        @CL_MIDI_RETURN_RTP: @[@"Réseau CL Console Return RTP", @"Network CL Console Return RTP", @"Réseau RTP MB Chris", @"Network RTP MB Chris"],
        @CL_MIDI_RETURN_TEST: @[], @CL_MIDI_DIRECT_RTP: @[]
    }; });
    return table;
}
static inline BOOL CLMIDIEqual(NSString *a, NSString *b) {
    return a && b && [a caseInsensitiveCompare:b] == NSOrderedSame;
}
static inline NSString *CLMIDICanonicalName(NSString *name) {
    for (NSString *canonical in CLMIDINameTable()) {
        if (CLMIDIEqual(name,canonical)) return canonical;
        for (NSString *alias in CLMIDINameTable()[canonical])
            if (CLMIDIEqual(name,alias)) return canonical;
    }
    return name;
}
static inline BOOL CLMIDINameMatches(NSString *name, NSString *role) {
    return CLMIDIEqual(CLMIDICanonicalName(name), CLMIDICanonicalName(role));
}
static inline NSArray<NSString *> *CLMIDICandidates(NSString *requested) {
    NSString *canonical=CLMIDICanonicalName(requested ?: @"");
    return [@[canonical ?: @""] arrayByAddingObjectsFromArray:CLMIDINameTable()[canonical] ?: @[]];
}
static inline void CLMIDILogSelection(NSString *requested, NSString *actual) {
    NSString *canonical=CLMIDICanonicalName(requested ?: @"");
    if (!actual.length || CLMIDIEqual(actual,canonical)) return;
    static NSMutableSet *logged; static dispatch_once_t once;
    dispatch_once(&once, ^{ logged=[NSMutableSet set]; });
    NSString *key=[NSString stringWithFormat:@"%@ -> %@", canonical, actual];
    @synchronized(logged) {
        if ([logged containsObject:key]) return;
        [logged addObject:key];
        BOOL decorated=[actual hasSuffix:canonical];
        NSLog(@"%@ : %@ : %@", canonical, decorated?@"nom CoreMIDI préfixé":@"fallback legacy", actual);
    }
}
static inline NSString *CLMIDIResolveName(NSArray<NSString *> *available, NSString *requested) {
    for (NSString *candidate in CLMIDICandidates(requested)) {
        for (NSString *actual in available) {
            if (CLMIDIEqual(candidate,actual)) {
                CLMIDILogSelection(requested,actual);
                return actual;
            }
        }
    }
    return nil;
}
static inline NSString *CLMIDIEndpointDisplayName(MIDIEndpointRef endpoint) {
    CFStringRef value=NULL;
    MIDIObjectGetStringProperty(endpoint,kMIDIPropertyDisplayName,&value);
    if(!value) MIDIObjectGetStringProperty(endpoint,kMIDIPropertyName,&value);
    return value ? CFBridgingRelease(value) : @"";
}
static inline MIDIEndpointRef CLMIDIFindEndpoint(BOOL source, NSString *requested) {
    NSMutableArray *names=[NSMutableArray array]; NSMutableArray *refs=[NSMutableArray array];
    ItemCount count=source?MIDIGetNumberOfSources():MIDIGetNumberOfDestinations();
    for(ItemCount i=0;i<count;i++) {
        MIDIEndpointRef ep=source?MIDIGetSource(i):MIDIGetDestination(i);
        [names addObject:CLMIDIEndpointDisplayName(ep)]; [refs addObject:@(ep)];
    }
    NSString *selected=CLMIDIResolveName(names,requested);
    NSUInteger index=selected?[names indexOfObject:selected]:NSNotFound;
    return index==NSNotFound?0:[refs[index] unsignedIntValue];
}
#endif
