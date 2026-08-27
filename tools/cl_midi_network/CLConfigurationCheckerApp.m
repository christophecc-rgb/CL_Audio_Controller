#import <AppKit/AppKit.h>
#import "CLConfigurationChecker.h"

@interface CLCheckerDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window; @property NSPopUpButton *roleMenu; @property NSTextField *profileLabel;
@property NSTextField *stateLabel; @property NSTextView *details; @property NSProgressIndicator *progress;
@property CLConfigurationProfile *profile; @property NSDictionary *inspection;
@end

@implementation CLCheckerDelegate
- (NSButton *)button:(NSString *)title x:(CGFloat)x y:(CGFloat)y width:(CGFloat)width action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, width, 32)]; button.title = title; button.bezelStyle = NSBezelStyleRounded; button.target = self; button.action = action; return button;
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame]; field.stringValue = text; field.editable = NO; field.selectable = YES; field.bezeled = NO; field.drawsBackground = NO; field.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size]; return field;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification; self.profile = [CLConfigurationProfile templateForRole:@"server"];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 650) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"CL MIDI & RTP Diagnostic"; [self.window center]; NSView *content = self.window.contentView; content.wantsLayer = YES; content.layer.backgroundColor = [NSColor colorWithRed:0.055 green:0.065 blue:0.085 alpha:1].CGColor;
    NSTextField *title = [self label:@"CL MIDI & RTP DIAGNOSTIC" frame:NSMakeRect(24, 602, 430, 28) size:19 bold:YES]; title.textColor = [NSColor colorWithRed:0.243 green:0.620 blue:0.839 alpha:1.0]; [content addSubview:title];
    NSImage *paradisLogo = [NSImage imageNamed:@"paradis_latin_logo"] ?: [[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"paradis_latin_logo" ofType:@"jpg"]];
    NSImageView *paradisLogoView = [[NSImageView alloc] initWithFrame:NSMakeRect(488, 596, 204, 40)]; paradisLogoView.image = paradisLogo; paradisLogoView.imageScaling = NSImageScaleProportionallyUpOrDown; paradisLogoView.imageAlignment = NSImageAlignRight; [content addSubview:paradisLogoView];
    self.profileLabel = [self label:self.profile.name frame:NSMakeRect(24, 560, 280, 26) size:13 bold:YES]; self.profileLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1]; [content addSubview:self.profileLabel];
    self.roleMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(318, 558, 190, 30)]; [self.roleMenu addItemsWithTitles:@[@"ABLETON LOCAL", @"ABLETON DISTANT"]]; self.roleMenu.target = self; self.roleMenu.action = @selector(roleChanged:); [content addSubview:self.roleMenu];
    [content addSubview:[self button:@"VÉRIFIER" x:526 y:558 width:166 action:@selector(check:)]];
    self.stateLabel = [self label:@"● EN ATTENTE" frame:NSMakeRect(24, 518, 668, 30) size:18 bold:YES]; self.stateLabel.textColor = NSColor.systemOrangeColor; [content addSubview:self.stateLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, 112, 668, 394)]; scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
    self.details = [[NSTextView alloc] initWithFrame:scroll.bounds]; self.details.editable = NO; self.details.selectable = YES; self.details.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular]; self.details.textColor = [NSColor colorWithWhite:0.88 alpha:1]; self.details.backgroundColor = [NSColor colorWithRed:0.035 green:0.042 blue:0.055 alpha:1]; self.details.string = @"Cliquez sur VÉRIFIER. Aucun réglage système ne sera modifié."; scroll.documentView = self.details; [content addSubview:scroll];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24, 88, 668, 12)]; self.progress.indeterminate = YES; self.progress.hidden = YES; [content addSubview:self.progress];
    [content addSubview:[self button:@"ENREGISTRER LE PROFIL" x:24 y:52 width:220 action:@selector(saveProfile:)]];
    [content addSubview:[self button:@"OUVRIR UN PROFIL" x:252 y:52 width:180 action:@selector(loadProfile:)]];
    [content addSubview:[self button:@"COPIER TOUT" x:24 y:14 width:124 action:@selector(copyAllText:)]];
    [content addSubview:[self button:@"EXPORTER TEXTE…" x:156 y:14 width:170 action:@selector(exportTextReport:)]];
    NSTextField *safety = [self label:@"Lecture seule · aucun réglage système n’est modifié." frame:NSMakeRect(338, 19, 354, 22) size:10 bold:NO]; safety.textColor = [NSColor colorWithWhite:0.58 alpha:1]; [content addSubview:safety];
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)roleChanged:(id)sender { (void)sender; self.profile = [CLConfigurationProfile templateForRole:self.roleMenu.indexOfSelectedItem == 0 ? @"server" : @"ableton_remote"]; self.profileLabel.stringValue = self.profile.name; self.stateLabel.stringValue = @"● EN ATTENTE"; self.details.string = @"Profil modèle chargé. Renseignez une référence par import JSON ou sauvegardez l’état courant après vérification."; }
- (void)check:(id)sender {
    (void)sender; self.progress.hidden = NO; [self.progress startAnimation:nil]; self.stateLabel.stringValue = @"● INSPECTION EN COURS"; self.details.string = @"Inspection locale en lecture seule…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *inspection = [[CLConfigurationInspector new] inspect]; CLConfigurationReport *report = [[CLConfigurationValidator new] validateProfile:self.profile inspection:inspection];
        NSMutableString *text = [NSMutableString string];
        NSArray *symbols = @[@"•", @"✓", @"⚠", @"✗"];
        for (NSDictionary *item in report.items) {
            NSInteger level = [item[@"level"] integerValue]; [text appendFormat:@"%@ %@ — %@\n", symbols[level], item[@"section"], item[@"title"]];
            if ([item[@"expected"] length]) [text appendFormat:@"  Attendu : %@\n", item[@"expected"]];
            if ([item[@"actual"] length]) [text appendFormat:@"  Actuel  : %@\n", item[@"actual"]];
            if (level >= CLCheckLevelWarning && [item[@"explanation"] length]) [text appendFormat:@"  Pourquoi : %@\n", item[@"explanation"]];
            if (level >= CLCheckLevelWarning && [item[@"action"] length]) [text appendFormat:@"  Action : %@\n", item[@"action"]];
            [text appendString:@"\n"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self.inspection = inspection; self.details.string = text; self.stateLabel.stringValue = [NSString stringWithFormat:@"● %@ · %lu erreur(s) · %lu alerte(s)", report.globalState, (unsigned long)report.errorCount, (unsigned long)report.warningCount]; self.stateLabel.textColor = report.errorCount ? NSColor.systemRedColor : (report.warningCount ? NSColor.systemOrangeColor : NSColor.systemGreenColor); [self.progress stopAnimation:nil]; self.progress.hidden = YES; });
    });
}
- (CLConfigurationProfile *)profileFromInspectionNamed:(NSString *)name {
    NSMutableDictionary *values = [self.profile.values mutableCopy]; values[@"profile_name"] = name;
    NSMutableDictionary *rtp = [values[@"rtp"] mutableCopy]; NSDictionary *actualRTP = self.inspection[@"rtp"] ?: @{}; rtp[@"local_session_name"] = actualRTP[@"local_session_name"] ?: @""; rtp[@"bonjour_name"] = actualRTP[@"bonjour_name"] ?: @"";
    NSArray *connections = actualRTP[@"connections"] ?: @[]; if (connections.count) rtp[@"expected_peer"] = connections.firstObject;
    NSMutableSet *sources = [NSMutableSet set], *destinations = [NSMutableSet set]; for (NSDictionary *endpoint in self.inspection[@"midi_endpoints"] ?: @[]) if ([endpoint[@"classification"] isEqualToString:@"rtp"]) { if ([endpoint[@"direction"] isEqualToString:@"source"]) [sources addObject:endpoint[@"name"]]; else [destinations addObject:endpoint[@"name"]]; }
    for (NSString *candidate in sources) if ([destinations containsObject:candidate]) { rtp[@"local_endpoint"] = candidate; break; } values[@"rtp"] = rtp;
    NSMutableDictionary *simulator = [values[@"simulator"] mutableCopy]; if ([simulator[@"transport"] isEqualToString:@"rtp"] && [rtp[@"local_endpoint"] length]) simulator[@"endpoint"] = rtp[@"local_endpoint"]; values[@"simulator"] = simulator;
    NSDictionary *status = self.inspection[@"server_status"] ?: @{};
    if ([self.profile.machineRole isEqualToString:@"server"] && status.count) {
        NSMutableDictionary *consoleReturn = [values[@"console_return"] mutableCopy] ?: [NSMutableDictionary dictionary];
        if ([status[@"console_return_mode"] isKindOfClass:NSString.class]) consoleReturn[@"mode"] = status[@"console_return_mode"];
        if ([status[@"console_return_source"] isKindOfClass:NSString.class]) consoleReturn[@"source"] = status[@"console_return_source"];
        values[@"console_return"] = consoleReturn;
    }
    return [CLConfigurationProfile profileWithValues:values error:nil];
}
- (void)showError:(NSError *)error { NSAlert *alert = [NSAlert new]; alert.messageText = @"Opération impossible"; alert.informativeText = error.localizedDescription ?: @"Erreur inconnue"; [alert runModal]; }
- (void)saveProfile:(id)sender {
    (void)sender; NSAlert *dialog = [NSAlert new]; dialog.messageText = @"Enregistrer le profil"; dialog.informativeText = @"Nom du profil de référence"; NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)]; input.stringValue = self.profile.name; dialog.accessoryView = input; [dialog addButtonWithTitle:@"Enregistrer"]; [dialog addButtonWithTitle:@"Annuler"]; if ([dialog runModal] != NSAlertFirstButtonReturn) return;
    CLConfigurationProfile *profile = [self profileFromInspectionNamed:input.stringValue]; NSURL *url = [[CLConfigurationProfile profilesDirectory] URLByAppendingPathComponent:[[input.stringValue stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"json"]]; NSError *error = nil; if (![profile writeToURL:url overwrite:NO error:&error]) { [self showError:error]; return; } self.profile = profile; self.profileLabel.stringValue = profile.name;
}
- (void)loadProfile:(id)sender { (void)sender; NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.allowedFileTypes = @[@"json"]; panel.allowsMultipleSelection = NO; panel.directoryURL = [CLConfigurationProfile profilesDirectory]; if ([panel runModal] != NSModalResponseOK) return; NSError *error = nil; CLConfigurationProfile *profile = [CLConfigurationProfile loadFromURL:panel.URL error:&error]; if (!profile) { [self showError:error]; return; } self.profile = profile; self.profileLabel.stringValue = profile.name; [self.roleMenu selectItemAtIndex:[profile.machineRole isEqualToString:@"server"] ? 0 : 1]; self.stateLabel.stringValue = @"● PROFIL CHARGÉ"; }
- (NSString *)textReport {
    NSString *role = [self.profile.machineRole isEqualToString:@"server"] ? @"ABLETON LOCAL" : @"ABLETON DISTANT";
    return [NSString stringWithFormat:@"CL MIDI & RTP DIAGNOSTIC\nProfil : %@\nRôle : %@\nÉtat : %@\n\n%@\n", self.profile.name ?: @"", role, self.stateLabel.stringValue ?: @"", self.details.string ?: @""];
}
- (void)copyAllText:(id)sender {
    (void)sender; NSPasteboard *pasteboard = NSPasteboard.generalPasteboard; [pasteboard clearContents]; [pasteboard setString:[self textReport] forType:NSPasteboardTypeString];
}
- (void)exportTextReport:(id)sender {
    (void)sender; NSSavePanel *panel = [NSSavePanel savePanel]; panel.allowedFileTypes = @[@"txt"]; panel.nameFieldStringValue = @"CL MIDI & RTP Diagnostic.txt"; if ([panel runModal] != NSModalResponseOK) return;
    NSError *error = nil; if (![[self textReport] writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]) [self showError:error];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray *arguments = NSProcessInfo.processInfo.arguments;
        if ([arguments containsObject:@"--inspect-json"]) {
            NSString *role = [arguments containsObject:@"--ableton-remote"] ? @"ableton_remote" : @"server"; CLConfigurationProfile *profile = [CLConfigurationProfile templateForRole:role]; NSDictionary *inspection = [[CLConfigurationInspector new] inspect]; CLConfigurationReport *report = [[CLConfigurationValidator new] validateProfile:profile inspection:inspection];
            NSDictionary *payload = @{@"profile": profile.values, @"inspection": inspection, @"global_state": report.globalState, @"items": report.items}; NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil]; fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); return 0;
        }
        NSApplication *application = NSApplication.sharedApplication; CLCheckerDelegate *delegate = [CLCheckerDelegate new]; application.delegate = delegate; [application run];
    } return 0;
}
