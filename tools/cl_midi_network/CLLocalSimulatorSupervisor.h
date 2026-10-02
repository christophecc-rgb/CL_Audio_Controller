// Local IAC lifecycle only. No MIDI packets or network configuration here.
#import <Foundation/Foundation.h>
#import <sys/file.h>
#import <sys/sysctl.h>
#import <libproc.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>

// Read argv as NUL-delimited tokens: names containing spaces must stay intact.
static NSArray<NSString *> *CLSimulatorArgv(pid_t pid) {
    int mib[] = {CTL_KERN, KERN_PROCARGS2, pid};
    char bytes[65536]; size_t size = sizeof(bytes);
    if (sysctl(mib, 3, bytes, &size, NULL, 0) || size < sizeof(int)) return @[];
    int argc = 0; memcpy(&argc, bytes, sizeof(argc));
    char *p = bytes + sizeof(int), *end = bytes + size;
    while (p < end && *p) p++; // executable path
    while (p < end && !*p) p++;
    NSMutableArray *args = [NSMutableArray array];
    for (int i = 0; i < argc && p < end; i++) {
        size_t n = strnlen(p, end - p);
        if (p + n >= end) return @[];
        NSString *s = [[NSString alloc] initWithBytes:p length:n encoding:NSUTF8StringEncoding];
        if (!s) return @[];
        [args addObject:s]; p += n + 1;
    }
    return args;
}
static NSString *CLSimulatorOption(NSArray *args, NSString *key) {
    NSUInteger i = [args indexOfObject:key];
    return i != NSNotFound && i + 1 < args.count ? args[i + 1] : @"";
}
static NSString *CLLocalSimulatorLabel(NSArray *args) {
    if (![[(NSString *)args.firstObject lastPathComponent] isEqualToString:@"CLYamahaConsoleSimulator"] ||
        ![CLSimulatorOption(args, @"--transport") isEqualToString:@"iac"] ||
        [args containsObject:@"--send-program"]) return nil;
    NSString *label = CLSimulatorOption(args, @"--label");
    NSString *channel = [label isEqualToString:@"CL5"] ? @"1" : [label isEqualToString:@"QL1"] ? @"2" : nil;
    // Scope migration cleanup to the explicitly requested local test route.
    if (!channel || ![CLSimulatorOption(args, @"--channel") isEqualToString:channel] ||
        ![@[@"CL MIDI Return Test", @"Gestionnaire IAC CL MIDI Return Test"] containsObject:CLSimulatorOption(args, @"--endpoint")] ||
        ![CLSimulatorOption(args, @"--input-endpoint") isEqualToString:@"Gestionnaire IAC Bus 1"]) return nil;
    return label;
}
static NSDictionary<NSNumber *, NSString *> *CLLocalSimulatorProcesses(void) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return nil; // fail closed for spawning, fail open for Show Control
    NSMutableData *storage = [NSMutableData dataWithLength:bytes + 4096];
    int count = proc_listpids(PROC_ALL_PIDS, 0, storage.mutableBytes, (int)storage.length) / sizeof(pid_t);
    if (count <= 0) return nil;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    pid_t *pids = storage.mutableBytes;
    for (int i = 0; i < count; i++) {
        struct proc_bsdinfo info;
        if (proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) || info.pbi_uid != getuid()) continue;
        NSString *label = CLLocalSimulatorLabel(CLSimulatorArgv(pids[i]));
        if (label) result[@(pids[i])] = label;
    }
    return result;
}

@interface CLLocalSimulatorSupervisor : NSObject
@property(copy) NSDictionary *(^inventory)(void);
@property(copy) NSNumber *(^launch)(NSString *label);
@property(copy) void (^stop)(NSNumber *pid);
@property(copy) BOOL (^healthy)(NSNumber *pid);
@property(copy) void (^log)(NSString *message);
@property NSMutableDictionary *owned, *retryAt, *failures, *startedAt;
@property NSString *generation, *endpoints, *state;
@property BOOL stopping;
@property NSMutableSet *retiring;
- (void)tick:(NSTimeInterval)now generation:(NSString *)generation endpoints:(NSString *)endpoints wanted:(NSSet *)wanted;
- (void)shutdown;
@end
@implementation CLLocalSimulatorSupervisor
- (instancetype)init {
    if ((self = [super init])) {
        _retiring = [NSMutableSet set]; _owned = [NSMutableDictionary dictionary]; _retryAt = [NSMutableDictionary dictionary];
        _failures = [NSMutableDictionary dictionary]; _startedAt = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)report:(NSString *)state {
    if (![_state isEqual:state]) { _state = state; if (_log) _log(state); }
}
- (void)tick:(NSTimeInterval)now generation:(NSString *)generation endpoints:(NSString *)endpoints wanted:(NSSet *)wanted {
    if (_stopping) return;
    NSDictionary *live = _inventory();
    if (!live) { [self report:@"failed: inventaire processus indisponible"]; return; }
    BOOL changed = ![(_generation ?: @"") isEqual:(generation ?: @"")] || ![(_endpoints ?: @"") isEqual:(endpoints ?: @"")];
    _generation = generation; _endpoints = endpoints;
    BOOL ready = generation.length && endpoints.length;
    // Unknown legacy children have no readiness proof: replace them, never adopt blindly.
    BOOL draining = NO;
    for (NSNumber *pid in live) {
        NSString *label = live[pid];
        if (changed || !ready || ![wanted containsObject:label] || ![_owned[label] isEqual:pid] || [_retiring containsObject:pid]) {
            [_retiring addObject:pid]; _stop(pid); draining = YES;
        }
    }
    for (NSString *label in _owned.allKeys.copy) {
        NSNumber *pid = _owned[label];
        if (!live[pid]) {
            BOOL planned = [_retiring containsObject:pid];
            [_retiring removeObject:pid];
            [_owned removeObjectForKey:label];
            if (!planned && !changed && ready && [wanted containsObject:label]) {
                NSUInteger n = MIN(5, [_failures[label] unsignedIntegerValue] + 1);
                _failures[label] = @(n); _retryAt[label] = @(now + MIN(30, 1 << n));
                [self report:[NSString stringWithFormat:@"failed: %@ arrêté, reprise avec backoff", label]];
            }
        }
    }
    [_retiring intersectSet:[NSSet setWithArray:live.allKeys]];
    if (draining) { [self report:@"stopping: attente de disparition de l’ancienne paire"]; return; }
    if (!ready) { [self report:generation.length ? @"waiting: endpoints IAC requis absents" : @"waiting: backend absent ou identité indisponible"]; return; }
    BOOL allHealthy = YES;
    for (NSString *label in wanted) {
        NSNumber *pid = _owned[label];
        if (pid && _healthy(pid)) {
            if (now - [_startedAt[label] doubleValue] >= 30) _failures[label] = @0;
            continue;
        }
        allHealthy = NO;
        if (pid) {
            if (now - [_startedAt[label] doubleValue] > 10) _stop(pid);
            continue;
        }
        if (now < [_retryAt[label] doubleValue]) continue;
        _startedAt[label] = @(now);
        pid = _launch(label);
        if (pid) _owned[label] = pid;
        else {
            NSUInteger n = MIN(5, [_failures[label] unsignedIntegerValue] + 1);
            _failures[label] = @(n); _retryAt[label] = @(now + MIN(30, 1 << n));
        }
    }
    [self report:allHealthy ? @"running: simulateurs locaux prêts" : @"starting/failed: attente READY ou backoff"];
}
- (void)shutdown {
    _stopping = YES;
    NSDictionary *live = _inventory();
    for (NSString *label in _owned) { NSNumber *pid = _owned[label]; if ([live[pid] isEqual:label]) _stop(pid); }
}
@end
