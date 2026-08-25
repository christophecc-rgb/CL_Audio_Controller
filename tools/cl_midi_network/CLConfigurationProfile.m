#import "CLConfigurationChecker.h"

static NSString *const CLConfigurationErrorDomain = @"com.claudio.configuration-checker";

@interface CLConfigurationProfile ()
@property NSDictionary *values;
@end

@implementation CLConfigurationProfile

+ (instancetype)profileWithValues:(NSDictionary *)values error:(NSError **)error {
    NSMutableArray *problems = [NSMutableArray array];
    if (![values isKindOfClass:NSDictionary.class]) [problems addObject:@"racine JSON invalide"];
    if ([values[@"schema_version"] integerValue] != 1) [problems addObject:@"schema_version doit valoir 1"];
    if (![values[@"profile_name"] isKindOfClass:NSString.class] || ![values[@"profile_name"] length]) [problems addObject:@"profile_name absent"];
    NSString *role = values[@"machine_role"];
    if (![@[@"server", @"ableton_remote"] containsObject:role]) [problems addObject:@"machine_role doit être server ou ableton_remote"];
    NSDictionary *rtp = values[@"rtp"];
    for (NSString *key in @[@"local_session_name", @"local_endpoint", @"bonjour_name", @"expected_peer"]) {
        if (![rtp[key] isKindOfClass:NSString.class]) [problems addObject:[@"rtp." stringByAppendingString:key]];
    }
    NSDictionary *midi = values[@"midi"];
    for (NSString *key in @[@"cl5_channel", @"ql1_channel"]) {
        NSInteger channel = [midi[key] integerValue];
        if (channel < 1 || channel > 16) [problems addObject:[@"canal MIDI invalide : " stringByAppendingString:key]];
    }
    if (problems.count) {
        if (error) *error = [NSError errorWithDomain:CLConfigurationErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:[problems componentsJoinedByString:@" · "]}];
        return nil;
    }
    CLConfigurationProfile *profile = [self new];
    profile.values = [values copy];
    return profile;
}

+ (instancetype)templateForRole:(NSString *)role {
    BOOL remote = [role isEqualToString:@"ableton_remote"];
    NSDictionary *values = @{
        @"schema_version": @1,
        @"profile_name": remote ? @"Mac Ableton distant" : @"Mac serveur",
        @"machine_role": remote ? @"ableton_remote" : @"server",
        @"ableton": @{@"host": remote ? NSProcessInfo.processInfo.hostName ?: @"" : @"127.0.0.1", @"osc_send_port": @11000, @"osc_reply_port": @11001},
        @"rtp": @{@"local_session_name": @"", @"local_endpoint": @"", @"bonjour_name": @"", @"expected_peer": @""},
        @"midi": @{@"cl5_channel": @1, @"ql1_channel": @2},
        @"simulator": @{@"transport": @"rtp", @"endpoint": @"", @"delay_ms": @80},
        @"console_return": @{@"mode": remote ? @"" : @"rtp_remote", @"source": @""},
        @"clf": @{@"cl5_path": [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/CL5.CLF"], @"ql1_path": [NSHomeDirectory() stringByAppendingPathComponent:@"Desktop/ql1.CLF"]},
    };
    return [self profileWithValues:values error:nil];
}

+ (NSURL *)profilesDirectory {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[[support URLByAppendingPathComponent:@"CL Audio" isDirectory:YES] URLByAppendingPathComponent:@"Configuration Profiles" isDirectory:YES] copy];
}

+ (instancetype)loadFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (!data) return nil;
    id values = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    return values ? [self profileWithValues:values error:error] : nil;
}

- (BOOL)writeToURL:(NSURL *)url overwrite:(BOOL)overwrite error:(NSError **)error {
    if (!overwrite && [NSFileManager.defaultManager fileExistsAtPath:url.path]) {
        if (error) *error = [NSError errorWithDomain:CLConfigurationErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:@"Un profil portant ce nom existe déjà."}];
        return NO;
    }
    if (![NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.values options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    return data && [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NSString *)name { return self.values[@"profile_name"] ?: @""; }
- (NSString *)machineRole { return self.values[@"machine_role"] ?: @""; }
@end
