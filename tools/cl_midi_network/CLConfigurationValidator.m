#import "CLConfigurationChecker.h"
#import <netdb.h>

static NSDictionary *CLItem(CLCheckLevel level, NSString *section, NSString *title, NSString *expected, NSString *actual, NSString *explanation, NSString *action) {
    return @{@"level": @(level), @"section": section ?: @"", @"title": title ?: @"", @"expected": expected ?: @"", @"actual": actual ?: @"", @"explanation": explanation ?: @"", @"action": action ?: @""};
}

static NSString *CLArgument(NSString *command, NSString *name) {
    NSRange range = [command rangeOfString:[name stringByAppendingString:@" "]]; if (range.location == NSNotFound) return @"";
    NSString *tail = [command substringFromIndex:NSMaxRange(range)];
    if ([tail hasPrefix:@"\""]) { NSRange end = [tail rangeOfString:@"\"" options:0 range:NSMakeRange(1, tail.length - 1)]; return end.location == NSNotFound ? @"" : [tail substringWithRange:NSMakeRange(1, end.location - 1)]; }
    return [tail componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet].firstObject ?: @"";
}

@interface CLConfigurationReport ()
@property NSArray<NSDictionary *> *items; @property NSString *globalState;
@property NSUInteger warningCount; @property NSUInteger errorCount;
@end

@implementation CLConfigurationReport
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items {
    if ((self = [super init])) { _items = [items copy]; for (NSDictionary *item in items) { NSInteger level = [item[@"level"] integerValue]; if (level == CLCheckLevelError) _errorCount++; else if (level == CLCheckLevelWarning) _warningCount++; } _globalState = _errorCount ? @"NON PRÊT" : (_warningCount ? @"ATTENTION" : @"PRÊT"); } return self;
}
@end

@implementation CLConfigurationValidator
- (CLConfigurationReport *)validateProfile:(CLConfigurationProfile *)profile inspection:(NSDictionary *)inspection {
    NSMutableArray *items = [NSMutableArray array]; NSDictionary *values = profile.values; NSDictionary *expectedRTP = values[@"rtp"]; NSDictionary *actualRTP = inspection[@"rtp"];
    NSString *expectedEndpoint = expectedRTP[@"local_endpoint"] ?: @""; NSArray *endpoints = inspection[@"midi_endpoints"] ?: @[];
    NSMutableSet *sourceNames = [NSMutableSet set], *destinationNames = [NSMutableSet set];
    for (NSDictionary *endpoint in endpoints) { NSString *name = endpoint[@"name"] ?: @""; if ([endpoint[@"direction"] isEqualToString:@"source"]) [sourceNames addObject:name]; else [destinationNames addObject:name]; }
    BOOL endpointOK = expectedEndpoint.length && [sourceNames containsObject:expectedEndpoint] && [destinationNames containsObject:expectedEndpoint];
    [items addObject:CLItem(endpointOK ? CLCheckLevelOK : CLCheckLevelError, @"CoreMIDI", @"Endpoint RTP local", expectedEndpoint, endpointOK ? expectedEndpoint : @"Absent comme paire entrée/sortie", @"Le peer Bonjour et l’endpoint CoreMIDI local sont des propriétés indépendantes.", @"Sélectionner dans Configuration audio et MIDI l’endpoint RTP local défini par ce profil.")];
    for (NSString *name in @[@"Gestionnaire IAC Bus 1", @"CL MIDI Return Test"]) if ([sourceNames containsObject:name] || [destinationNames containsObject:name]) [items addObject:CLItem(CLCheckLevelOK, @"CoreMIDI", name, name, name, @"Endpoint local détecté.", @"")];

    NSString *sessionExpected = expectedRTP[@"local_session_name"] ?: @"", *sessionActual = actualRTP[@"local_session_name"] ?: @"";
    [items addObject:CLItem(!sessionExpected.length ? CLCheckLevelInfo : ([sessionExpected isEqualToString:sessionActual] ? CLCheckLevelOK : CLCheckLevelError), @"RTP", @"Session RTP locale", sessionExpected, sessionActual, @"Nom de la session locale du Mac courant.", @"Corriger le profil ou la session locale dans Configuration audio et MIDI.")];
    NSString *bonjourExpected = expectedRTP[@"bonjour_name"] ?: @"", *bonjourActual = actualRTP[@"bonjour_name"] ?: @"";
    [items addObject:CLItem(!bonjourExpected.length ? CLCheckLevelInfo : ([bonjourExpected isEqualToString:bonjourActual] ? CLCheckLevelOK : CLCheckLevelWarning), @"RTP", @"Nom Bonjour local", bonjourExpected, bonjourActual, @"Ce nom annonce ce Mac sur le réseau ; ce n’est pas le peer distant.", @"Vérifier le nom réseau de la session RTP locale.")];
    NSString *peer = expectedRTP[@"expected_peer"] ?: @""; NSArray *connections = actualRTP[@"connections"] ?: @[];
    [items addObject:CLItem(!peer.length ? CLCheckLevelInfo : ([connections containsObject:peer] ? CLCheckLevelOK : CLCheckLevelError), @"RTP", @"Peer RTP attendu", peer, [connections componentsJoinedByString:@", "], @"La connexion active est comparée au peer distant attendu, jamais au nom de l’endpoint local.", @"Connecter le correspondant Bonjour attendu dans Configuration audio et MIDI.")];

    NSArray *processes = inspection[@"processes"] ?: @[]; NSMutableDictionary *counts = [NSMutableDictionary dictionary]; BOOL foundSimulator = NO;
    NSDictionary *simulatorProfile = values[@"simulator"] ?: @{}; NSDictionary *midi = values[@"midi"] ?: @{};
    for (NSDictionary *process in processes) {
        NSString *command = process[@"command"] ?: @"", *path = process[@"path"] ?: @"";
        for (NSString *name in @[@"CL MIDI Network Assistant", @"CL MIDI RTP Agent", @"CLMIDINetworkGuardian", @"CLYamahaConsoleSimulator", @"app.py"]) if ([command containsString:name]) counts[name] = @([counts[name] integerValue] + 1);
        if ([process[@"app_translocation"] boolValue]) [items addObject:CLItem(CLCheckLevelError, @"Processus", @"App Translocation", @"~/Applications ou /Applications", path, @"Une application transloquée peut charger des ressources depuis un chemin temporaire instable.", @"Fermer cette instance et lancer l’application installée.")];
        else if ([process[@"development_build"] boolValue]) [items addObject:CLItem(CLCheckLevelWarning, @"Processus", @"Build de développement active", @"Application installée", path, @"Cette instance provient d’un dossier de développement ou de distribution.", @"Fermer cette instance puis lancer l’application installée.")];
        if (![command containsString:@"CLYamahaConsoleSimulator"]) continue; foundSimulator = YES;
        NSString *label = CLArgument(command, @"--label"), *endpoint = CLArgument(command, @"--endpoint"), *transport = CLArgument(command, @"--transport"), *channel = CLArgument(command, @"--channel"), *delay = CLArgument(command, @"--delay-ms");
        NSString *expectedChannel = [label caseInsensitiveCompare:@"CL5"] == NSOrderedSame ? [midi[@"cl5_channel"] stringValue] : [midi[@"ql1_channel"] stringValue];
        BOOL endpointMatches = [endpoint isEqualToString:simulatorProfile[@"endpoint"] ?: @""] && [sourceNames containsObject:endpoint] && [destinationNames containsObject:endpoint];
        [items addObject:CLItem(endpointMatches ? CLCheckLevelOK : CLCheckLevelError, @"Simulateur", [NSString stringWithFormat:@"%@ · endpoint RTP local", label], simulatorProfile[@"endpoint"], endpoint, @"Le processus doit utiliser un endpoint présent sur ce Mac, pas une valeur provenant du Mac serveur.", [NSString stringWithFormat:@"Sélectionner l’endpoint RTP local « %@ ».", simulatorProfile[@"endpoint"] ?: @""])];
        BOOL argumentsOK = [transport isEqualToString:simulatorProfile[@"transport"]] && [channel isEqualToString:expectedChannel] && [delay integerValue] == [simulatorProfile[@"delay_ms"] integerValue];
        [items addObject:CLItem(argumentsOK ? CLCheckLevelOK : CLCheckLevelError, @"Simulateur", [NSString stringWithFormat:@"%@ · paramètres", label], [NSString stringWithFormat:@"transport %@ · canal %@ · délai %@ ms", simulatorProfile[@"transport"], expectedChannel, simulatorProfile[@"delay_ms"]], [NSString stringWithFormat:@"transport %@ · canal %@ · délai %@ ms", transport, channel, delay], @"Canaux et délai restent configurables dans le profil.", @"Relancer le simulateur avec les paramètres du profil.")];
    }
    if (!foundSimulator) [items addObject:CLItem(CLCheckLevelInfo, @"Simulateur", @"Simulateurs CL5 / QL1", @"Selon le scénario", @"Aucun processus", @"L’absence est normale si le test distant n’est pas actif.", @"")];
    [counts enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSNumber *count, BOOL *stop) { (void)stop; if (count.integerValue > 1 && ![name isEqualToString:@"CLYamahaConsoleSimulator"]) [items addObject:CLItem(CLCheckLevelWarning, @"Processus", @"Doublon suspect", @"Une instance", [NSString stringWithFormat:@"%@ instances de %@", count, name], @"Plusieurs instances peuvent se disputer les ports ou publier des états contradictoires.", @"Fermer manuellement l’ancienne instance après vérification.")]; }];

    NSDictionary *ports = inspection[@"ports"] ?: @{}; BOOL server = [profile.machineRole isEqualToString:@"server"];
    for (NSNumber *port in @[@5050, @11000, @11001, @63123]) { NSArray *owners = ports[port.stringValue] ?: @[]; BOOL required = server ? [@[@5050, @11001, @63123] containsObject:port] : [port isEqual:@11000]; [items addObject:CLItem(owners.count ? CLCheckLevelOK : (required ? CLCheckLevelError : CLCheckLevelInfo), @"Réseau", [NSString stringWithFormat:@"Port %@", port], required ? @"Occupé par CL Audio" : @"Selon le rôle", owners.count ? [owners componentsJoinedByString:@"\n"] : @"Libre", @"Contrôle en lecture seule du processus occupant le port.", @"Lancer le composant prévu par le profil ou fermer manuellement l’ancienne instance.")]; }

    if (!server) {
        NSString *host = values[@"ableton"][@"host"] ?: @""; __block BOOL resolved = NO; dispatch_semaphore_t dnsDone = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ struct addrinfo hints = {0}, *addresses = NULL; hints.ai_socktype = SOCK_DGRAM; resolved = host.length && getaddrinfo(host.UTF8String, NULL, &hints, &addresses) == 0; if (addresses) freeaddrinfo(addresses); dispatch_semaphore_signal(dnsDone); });
        dispatch_semaphore_wait(dnsDone, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)));
        [items addObject:CLItem(resolved ? CLCheckLevelOK : CLCheckLevelError, @"Ableton / OSC", @"Résolution du host Ableton", host, resolved ? @"Résolu" : @"Introuvable", @"La vérification DNS ne transmet aucune commande à Ableton.", @"Corriger le hostname ou l’adresse IP dans le profil.")];
        BOOL abletonRunning = NO; for (NSDictionary *process in processes) if ([process[@"command"] containsString:@"Ableton Live"]) { abletonRunning = YES; break; }
        [items addObject:CLItem(abletonRunning ? CLCheckLevelOK : CLCheckLevelWarning, @"Ableton / OSC", @"Ableton Live", @"Processus local actif", abletonRunning ? @"Actif" : @"Non détecté", @"Le contrôle reste passif et ne modifie jamais le transport Ableton.", @"Lancer Ableton Live si ce Mac doit émettre les Program Change.")];
    }

    NSDictionary *status = inspection[@"server_status"] ?: @{};
    if (server) {
        NSString *mode = status[@"console_return_mode"] ?: @"", *source = status[@"console_return_source"] ?: @""; NSDictionary *expectedReturn = values[@"console_return"] ?: @{};
        BOOL returnOK = status.count && (![expectedReturn[@"mode"] length] || [mode isEqualToString:expectedReturn[@"mode"]]) && (![expectedReturn[@"source"] length] || [source isEqualToString:expectedReturn[@"source"]]);
        [items addObject:CLItem(returnOK ? CLCheckLevelOK : CLCheckLevelError, @"Retour console", @"État serveur /status", [NSString stringWithFormat:@"mode %@ · source %@", expectedReturn[@"mode"], expectedReturn[@"source"]], status.count ? [NSString stringWithFormat:@"mode %@ · source %@", mode, source] : @"Serveur indisponible", @"Lecture non destructive de l’état expected / returned publié par le serveur.", @"Vérifier le serveur et la source de retour configurée.")];
        NSDictionary *midiConsole = [status[@"midi_console"] isKindOfClass:NSDictionary.class] ? status[@"midi_console"] : @{};
        for (NSString *consoleName in @[@"cl5", @"ql1"]) {
            NSDictionary *console = [midiConsole[consoleName] isKindOfClass:NSDictionary.class] ? midiConsole[consoleName] : @{};
            id expected = console[@"expected_midi_program"] ?: console[@"expected_program"]; id returned = console[@"returned_midi_program"] ?: console[@"returned_program"];
            if (expected == NSNull.null) expected = nil; if (returned == NSNull.null) returned = nil;
            if (!expected && !returned) continue; BOOL synchronized = expected && returned && [expected integerValue] == [returned integerValue];
            [items addObject:CLItem(synchronized ? CLCheckLevelOK : CLCheckLevelWarning, @"Retour console", [consoleName.uppercaseString stringByAppendingString:@" · expected / returned"], [expected description], [returned description], @"Comparaison passive des derniers Program Change publiés par le serveur.", @"Vérifier l’âge du retour et le routage console si les valeurs divergent.")];
        }
    }
    NSDictionary *clf = values[@"clf"] ?: @{}; for (NSString *key in @[@"cl5_path", @"ql1_path"]) { NSString *path = clf[key] ?: @""; BOOL readable = [NSFileManager.defaultManager isReadableFileAtPath:path]; [items addObject:CLItem(readable ? CLCheckLevelOK : (server ? CLCheckLevelError : CLCheckLevelInfo), @"CLF", [key hasPrefix:@"cl5"] ? @"Bibliothèque CL5" : @"Bibliothèque QL1", path, readable ? @"Présente et lisible" : @"Absente", @"Le Checker ne modifie ni offsets ni lookups CLF.", @"Choisir un chemin CLF lisible dans le profil.")]; }
    return [[CLConfigurationReport alloc] initWithItems:items];
}
@end
