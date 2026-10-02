#import "../../tools/cl_midi_network/CLLocalSimulatorSupervisor.h"
#import "../../tools/cl_midi_network/CLSimulatorProcessLease.h"
#import <sys/wait.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
int main(void) { @autoreleasepool {
    NSMutableDictionary *live = [NSMutableDictionary dictionary];
    NSMutableSet *ready = [NSMutableSet set], *stopped = [NSMutableSet set];
    __block int nextPID = 100, launches = 0;
    CLLocalSimulatorSupervisor *s = [CLLocalSimulatorSupervisor new];
    s.inventory = ^{ return live.copy; };
    s.launch = ^NSNumber *(NSString *label) { NSNumber *pid = @(++nextPID); live[pid] = label; launches++; return pid; };
    s.stop = ^(NSNumber *pid) { [stopped addObject:pid]; };
    s.healthy = ^BOOL(NSNumber *pid) { return [ready containsObject:pid]; };
    NSSet *pair = [NSSet setWithArray:@[@"CL5", @"QL1"]];
    [s tick:0 generation:@"a" endpoints:@"1:2" wanted:pair];
    CHECK(live.count == 2 && launches == 2);
    [ready addObjectsFromArray:live.allKeys];
    [s tick:2 generation:@"a" endpoints:@"1:2" wanted:pair];
    CHECK(launches == 2 && [s.state hasPrefix:@"running"]);
    // Generation changes wait for actual exit, even beyond multiple ticks.
    [s tick:4 generation:@"b" endpoints:@"1:2" wanted:pair];
    CHECK(stopped.count == 2 && launches == 2);
    [s tick:6 generation:@"b" endpoints:@"1:2" wanted:pair]; CHECK(launches == 2);
    [live removeAllObjects]; [stopped removeAllObjects];
    [s tick:8 generation:@"b" endpoints:@"1:2" wanted:pair]; CHECK(launches == 4 && live.count == 2);
    [ready addObjectsFromArray:live.allKeys];
    NSNumber *dead = s.owned[@"CL5"], *survivor = s.owned[@"QL1"];
    [live removeObjectForKey:dead];
    [s tick:10 generation:@"b" endpoints:@"1:2" wanted:pair]; CHECK(launches == 4);
    [s tick:11 generation:@"b" endpoints:@"1:2" wanted:pair]; CHECK(launches == 4);
    [s tick:12 generation:@"b" endpoints:@"1:2" wanted:pair]; CHECK(launches == 5 && [s.owned[@"QL1"] isEqual:survivor]);
    [s tick:14 generation:@"b" endpoints:nil wanted:pair]; CHECK(stopped.count == 2);
    [live removeAllObjects]; [stopped removeAllObjects];
    for (int i = 16; i < 100; i += 2) [s tick:i generation:@"b" endpoints:nil wanted:pair];
    CHECK(launches == 5 && [s.state containsString:@"endpoints IAC"]);
    [s tick:100 generation:@"b" endpoints:@"3:4" wanted:pair]; CHECK(launches == 7 && live.count == 2);
    [ready addObjectsFromArray:live.allKeys];
    [s tick:102 generation:nil endpoints:@"3:4" wanted:pair]; CHECK(stopped.count == 2);
    [live removeAllObjects]; [stopped removeAllObjects];
    [s tick:104 generation:nil endpoints:@"3:4" wanted:pair]; CHECK(launches == 7);
    [s tick:106 generation:@"c" endpoints:@"3:4" wanted:pair]; CHECK(launches == 9);
    [s shutdown]; CHECK(stopped.count == 2);
    [s tick:108 generation:@"c" endpoints:@"3:4" wanted:pair]; CHECK(launches == 9);
    // Unknown legacy duplicates are drained before any launch.
    CLLocalSimulatorSupervisor *legacy = [CLLocalSimulatorSupervisor new];
    legacy.inventory = s.inventory; legacy.launch = s.launch; legacy.stop = s.stop; legacy.healthy = s.healthy;
    live[@999] = @"CL5";
    [legacy tick:0 generation:@"c" endpoints:@"3:4" wanted:pair]; CHECK(launches == 9 && stopped.count == 3);
    NSArray *args = @[@"/tmp/CLYamahaConsoleSimulator", @"--label", @"CL5", @"--channel", @"1", @"--transport", @"iac", @"--endpoint", @"CL MIDI Return Test", @"--input-endpoint", @"Gestionnaire IAC Bus 1"];
    CHECK([CLLocalSimulatorLabel(args) isEqual:@"CL5"]);
    CHECK(CLLocalSimulatorLabel([args arrayByAddingObjectsFromArray:@[@"--send-program", @"1"]]) == nil);
    CHECK(CLLocalSimulatorLabel(@[@"other", @"--label", @"CL5"]) == nil);
    // A child that never emits READY is stopped, then retries with backoff.
    [live removeAllObjects]; [ready removeAllObjects]; [stopped removeAllObjects];
    CLLocalSimulatorSupervisor *hung = [CLLocalSimulatorSupervisor new];
    hung.inventory = s.inventory; hung.launch = s.launch; hung.stop = s.stop; hung.healthy = s.healthy;
    [hung tick:0 generation:@"x" endpoints:@"1:2" wanted:pair];
    int before = launches;
    [hung tick:12 generation:@"x" endpoints:@"1:2" wanted:pair]; CHECK(stopped.count == 2);
    [live removeAllObjects];
    [hung tick:14 generation:@"x" endpoints:@"1:2" wanted:pair]; CHECK(launches == before);
    [hung tick:16 generation:@"x" endpoints:@"1:2" wanted:pair]; CHECK(launches == before + 2);
    // A real interprocess flock excludes a second launcher, without touching production locks.
    NSString *label = [NSString stringWithFormat:@"test-%d", getpid()];
    int lease = CLSimulatorProcessLease(label); CHECK(lease >= 0);
    pid_t child = fork(); CHECK(child >= 0);
    if (!child) { close(lease); _exit(CLSimulatorProcessLease(label) < 0 ? 0 : 1); }
    int status; waitpid(child, &status, 0); CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    close(lease); int again = CLSimulatorProcessLease(label); CHECK(again >= 0); close(again);
    puts("PASS: initial pair, healthy reuse, generation replacement, death/backoff, absent/returned endpoints, backend disappearance, shutdown, legacy duplicates, argv scope, process lease");
} return 0; }
