#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <Carbon/Carbon.h>
#import "ATVVADPCM.h"
#import "ModifierEdges.h"
#import "ATVVCaptureGate.h"
#import <unistd.h>

static NSString * const ATVVServiceUUID = @"AB5E0001-5A21-4F05-BC7D-AF01F617B664";
static NSString * const ATVVCommandUUID = @"AB5E0002-5A21-4F05-BC7D-AF01F617B664";
static NSString * const ATVVAudioUUID = @"AB5E0003-5A21-4F05-BC7D-AF01F617B664";
static NSString * const ATVVControlUUID = @"AB5E0004-5A21-4F05-BC7D-AF01F617B664";
static NSString * const kLastChromecastPeripheralUUIDKey = @"lastChromecastPeripheralUUID";
static const int kRemoteVendorID = 0x18D1;
static const int kRemoteProductID = 0x9450;
static const int64_t kSyntheticKeyMarker = 0x564F4B4945;
static const int64_t kKKvoiceSyntheticKeyMarker = 0x4B4B564F494345;
static NSObject *gOutputLock;

@class RemoteHelper;

static void Emit(NSString *type, NSDictionary *fields) {
    if (!gOutputLock) gOutputLock = [NSObject new];
    NSMutableDictionary *object = fields ? [fields mutableCopy] : [NSMutableDictionary new];
    object[@"type"] = type;
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys error:&error];
    if (!json) return;
    NSMutableData *line = [json mutableCopy];
    const uint8_t newline = '\n';
    [line appendBytes:&newline length:1];
    @synchronized (gOutputLock) {
        [[NSFileHandle fileHandleWithStandardOutput] writeData:line];
    }
}

static void Log(NSString *message) {
    NSData *data = [[message stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [[NSFileHandle fileHandleWithStandardError] writeData:data];
}

@interface RemoteHelper : NSObject <CBCentralManagerDelegate, CBPeripheralDelegate>
@property(nonatomic, strong) CBCentralManager *central;
@property(nonatomic, strong) CBPeripheral *peripheral;
@property(nonatomic, strong) CBCharacteristic *commandCharacteristic;
@property(nonatomic, strong) CBCharacteristic *audioCharacteristic;
@property(nonatomic, strong) CBCharacteristic *controlCharacteristic;
@property(nonatomic, strong) NSTimer *keepAliveTimer;
@property(nonatomic, strong) NSTimer *discoveryTimer;
@property(nonatomic, strong) NSTimer *discoveryWindowTimer;
@property(nonatomic, assign) BOOL scanningEmitted;
@property(nonatomic, assign) BOOL hidDevicePresent;
@property(nonatomic, strong) NSDictionary *keyboardConfig;
@property(nonatomic, strong) NSDictionary *buttonMappings;
@property(nonatomic, assign) IOHIDManagerRef hidManager;
@property(nonatomic, assign) CFMachPortRef eventTap;
@property(nonatomic, assign) CFRunLoopSourceRef eventTapSource;
@property(nonatomic, assign) NSInteger capsVersion;
@property(nonatomic, assign) NSInteger codec;
@property(nonatomic, assign) NSInteger frameSize;
@property(nonatomic, assign) uint8_t streamID;
@property(nonatomic, assign) uint16_t sequence;
@property(nonatomic, assign) NSInteger predictor;
@property(nonatomic, assign) NSInteger stepIndex;
@property(nonatomic, assign) BOOL isStreaming;
@property(nonatomic, assign) BOOL keepCaptureOpen;
@property(nonatomic, assign) ATVVCaptureGate captureGate;
@property(nonatomic, assign) BOOL voiceButtonPressed;
@property(nonatomic, assign) NSUInteger audioFrameCount;
@property(nonatomic, assign) BOOL escapeCancelActive;
@property(nonatomic, assign) BOOL escapeCancelDown;
@property(nonatomic, assign) BOOL appSwitcherActive;
@property(nonatomic, assign) BOOL appSwitcherCommandDown;
@property(nonatomic, assign) BOOL appSwitcherEscapeDown;
@property(nonatomic, assign) NSUInteger appSwitcherGeneration;
@property(nonatomic, assign) BOOL keyboardTriggerDown;
@property(nonatomic, assign) KKModifierState keyboardModifierState;
@property(nonatomic, assign) BOOL filePickerOpen;
@property(nonatomic, assign) BOOL hasPendingSyncBeforeStart;
@property(nonatomic, assign) BOOL stopped;
@property(nonatomic, copy) NSString *snapnotePendingActionId;
@property(nonatomic, assign) BOOL snapnoteShortcutSent;
@property(nonatomic, strong) NSString *lastUsage;
@property(nonatomic, assign) NSInteger scanRetryCount;
@property(nonatomic, assign) BOOL scanRetryScheduled;
@property(nonatomic, assign) BOOL audioNotificationReady;
@property(nonatomic, assign) BOOL controlNotificationReady;
@property(nonatomic, assign) BOOL capabilityRequestOutstanding;
@property(nonatomic, assign) BOOL pendingMicrophoneOpen;
@property(nonatomic, assign) NSUInteger capabilityHandshakeGeneration;
@property(nonatomic, assign) BOOL connectAttemptPending;
@property(nonatomic, assign) NSUInteger connectAttemptGeneration;
@property(nonatomic, strong) NSNumber *previous8kSample;

- (void)handleReportID:(uint32_t)reportID data:(NSData *)data;
- (BOOL)handleKeyboardType:(CGEventType)type event:(CGEventRef)event;
- (void)handleCommand:(NSDictionary *)message;
- (void)postTarget:(NSString *)target;
- (void)postStringAndEnter:(NSString *)text;
- (void)sendFocusMainChatShortcutToApplication:(NSString *)bundleId attempt:(NSUInteger)attempt;
- (void)postKeyCode:(uint16_t)keyCode modifiers:(NSArray<NSString *> *)modifiers;
- (void)postKeyCodeWithoutText:(uint16_t)keyCode keyDown:(BOOL)down flags:(CGEventFlags)flags;
- (void)postOptionLShortcutWithoutText;
- (void)prepareSnapNoteAndTriggerGlobalNewNote:(NSString *)actionId shortcut:(NSString *)shortcut;
- (void)sendSnapNoteGlobalNewNoteShortcutWithActionId:(NSString *)actionId shortcut:(NSString *)shortcut attempt:(NSUInteger)attempt;
- (void)postSnapNoteGlobalNewNoteShortcut:(NSString *)shortcut;
- (void)completeSnapNoteNewNoteActionWithActionId:(NSString *)actionId;
- (void)prepareAppleNotesAndCreateNewNoteWithActionId:(NSString *)actionId tag:(NSString *)tag;
- (void)waitForAppleNotesFrontmostAndSendNewNoteWithActionId:(NSString *)effectiveActionId
                                            originalActionId:(NSString *)originalActionId
                                                         tag:(NSString *)tag
                                                     attempt:(NSUInteger)attempt;
- (void)completeAppleNotesNewNoteWithActionId:(NSString *)effectiveActionId
                             originalActionId:(NSString *)originalActionId
                                          tag:(NSString *)tag;
- (void)postKeyCode:(uint16_t)keyCode keyDown:(BOOL)down flags:(CGEventFlags)flags;
- (BOOL)resolvePrintableASCIICharacter:(UniChar)character
                                layout:(const UCKeyboardLayout *)layout
                               keyCode:(uint16_t *)keyCode
                                 flags:(CGEventFlags *)flags;
- (NSArray<NSDictionary *> *)physicalKeyStrokesForASCIIText:(NSString *)text;
- (void)postPhysicalKeyStroke:(NSDictionary *)stroke;
- (void)beginAppSwitcher;
- (void)beginAppSwitcherWithDirection:(NSInteger)direction;
- (void)finishAppSwitcher:(BOOL)commit;
- (void)restartAppSwitcherTimeout;
- (void)chooseFileForButton:(NSString *)buttonId pickerId:(NSString *)pickerId;
- (NSArray<NSDictionary *> *)installedApplications;
- (void)resetATVVState;
- (BOOL)armCaptureProbe:(NSString *)origin;
- (void)requestCapabilitiesIfReady;
- (void)failCurrentPeripheral:(NSString *)message;
- (void)discoverRemote;
- (void)startDiscoveryWindowWithDuration:(NSTimeInterval)duration;
- (void)pollOrScanForRemote;
- (void)startDiscoveryTimer;
- (void)stopDiscoveryTimer;
- (BOOL)refreshHIDDevicePresence;
- (void)releasePeripheralForSystemPairingIfNeeded;
- (void)scheduleHIDPresenceGuardForPeripheral:(CBPeripheral *)peripheral;
- (CBPeripheral *)retrieveKnownChromecastPeripheral;
- (void)rememberChromecastPeripheral:(CBPeripheral *)peripheral;
- (void)connectPeripheral:(CBPeripheral *)peripheral;
- (void)retryScan;
- (void)teardownKeyboardTap;
- (void)restartKeyboardTap;
- (void)startTapOrderGuard;
- (void)stopTapOrderGuard;
@end

static void HIDInputReportCallback(
    void *context, IOReturn result, void *sender, IOHIDReportType type,
    uint32_t reportID, uint8_t *report, CFIndex reportLength
) {
    if (!context || result != kIOReturnSuccess || reportLength <= 0) return;
    RemoteHelper *helper = (__bridge RemoteHelper *)context;
    [helper handleReportID:reportID data:[NSData dataWithBytes:report length:(NSUInteger)reportLength]];
}

static void HIDDeviceMatchedCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    if (result == kIOReturnSuccess) {
        Emit(@"hid_connected", @{@"vendorId": @(kRemoteVendorID), @"productId": @(kRemoteProductID)});
        if (context) {
            RemoteHelper *helper = (__bridge RemoteHelper *)context;
            dispatch_async(dispatch_get_main_queue(), ^{
                helper.hidDevicePresent = YES;
                if (!helper.peripheral && !helper.stopped && helper.central.state == CBManagerStatePoweredOn) {
                    [helper startDiscoveryWindowWithDuration:15.0];
                }
            });
        }
    }
}

static void HIDDeviceRemovedCallback(void *context, IOReturn result, void *sender, IOHIDDeviceRef device) {
    Emit(@"hid_disconnected", @{});
    if (context) {
        RemoteHelper *helper = (__bridge RemoteHelper *)context;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![helper refreshHIDDevicePresence]) {
                [helper releasePeripheralForSystemPairingIfNeeded];
            }
        });
    }
}

static CGEventRef KeyboardEventCallback(
    CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon
) {
    if (!refcon) return event;
    RemoteHelper *helper = (__bridge RemoteHelper *)refcon;
    return [helper handleKeyboardType:type event:event] ? NULL : event;
}

@implementation RemoteHelper

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _keyboardConfig = @{@"enabled": @NO, @"key": @"Fn", @"modifiers": @[], @"captureCancelOnly": @NO};
    _buttonMappings = @{};
    _central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    [self startInputReader];
    Emit(@"helper_started", @{@"vendorId": @(kRemoteVendorID), @"productId": @(kRemoteProductID)});
    return self;
}

- (void)start {
    if (self.central.state == CBManagerStatePoweredOn) [self discoverRemote];
    Emit(@"applications", @{ @"applications": [self installedApplications] });
}

- (void)startInputReader {
    __weak RemoteHelper *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableData *buffer = [NSMutableData data];
        uint8_t chunk[2048];
        ssize_t count = 0;
        while ((count = read(STDIN_FILENO, chunk, sizeof(chunk))) > 0) {
            [buffer appendBytes:chunk length:(NSUInteger)count];
            uint8_t *bytes = (uint8_t *)buffer.mutableBytes;
            NSUInteger start = 0;
            for (NSUInteger i = 0; i < buffer.length; i++) {
                if (bytes[i] != '\n') continue;
                NSData *line = [buffer subdataWithRange:NSMakeRange(start, i - start)];
                start = i + 1;
                NSDictionary *message = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                if (![message isKindOfClass:[NSDictionary class]]) continue;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf handleCommand:message];
                });
            }
            if (start > 0) [buffer replaceBytesInRange:NSMakeRange(0, start) withBytes:NULL length:0];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf shutdown];
        });
    });
}

- (void)handleCommand:(NSDictionary *)message {
    NSString *type = message[@"type"];
    if ([type isEqualToString:@"configure"]) {
        NSDictionary *config = message[@"config"];
        if (![config isKindOfClass:[NSDictionary class]]) return;
        NSDictionary *trigger = config[@"keyboardTrigger"];
        NSDictionary *mappings = config[@"buttonMappings"];
        NSString *hidSource = [config[@"hidSource"] isKindOfClass:[NSString class]] ? config[@"hidSource"] : @"iokit";
        if ([trigger isKindOfClass:[NSDictionary class]]) {
            // Passthrough is intentionally constrained to one unmodified key.
            // The host is responsible for checking that it exactly matches the
            // input application's shortcut; the helper cannot know that setting.
            BOOL passThrough = [trigger[@"passThrough"] boolValue];
            id rawMods = trigger[@"modifiers"];
            NSArray *mods = [rawMods isKindOfClass:[NSArray class]] ? rawMods : @[];
            if (self.keyboardTriggerDown && ![trigger isEqualToDictionary:self.keyboardConfig]) {
                Emit(@"keyboard_trigger_error", @{@"message": @"Release the physical trigger before changing its configuration."});
                return;
            }
            if (passThrough && ((rawMods && ![rawMods isKindOfClass:[NSArray class]]) || mods.count != 0 || [trigger[@"captureCancelOnly"] boolValue])) {
                Emit(@"keyboard_trigger_error", @{@"message": @"Passthrough requires one unmodified key."});
                return;
            }
            self.keyboardConfig = trigger;
        }
        if ([mappings isKindOfClass:[NSDictionary class]]) self.buttonMappings = mappings;
        if ([hidSource isEqualToString:@"iokit"]) [self startHID];
        else [self stopHID];
        [self restartKeyboardTap];
        Emit(@"configured", @{@"captureCancelOnly": @([self.keyboardConfig[@"captureCancelOnly"] boolValue])});
    } else if ([type isEqualToString:@"cancel_snapnote_action"]) {
        // handleCommand is dispatched to the main queue. Clear pending before
        // acknowledging, so later shortcut/dot callbacks cannot execute.
        NSString *actionId = [message[@"actionId"] isKindOfClass:[NSString class]] ? message[@"actionId"] : @"";
        BOOL prevented = actionId.length > 0 && [self.snapnotePendingActionId isEqualToString:actionId];
        BOOL shortcutSent = prevented && self.snapnoteShortcutSent;
        if (prevented) {
            self.snapnotePendingActionId = nil;
            self.snapnoteShortcutSent = NO;
        }
        Emit(@"snapnote_action_cancelled", @{@"actionId": actionId, @"prevented": @(prevented), @"shortcutSent": @(shortcutSent)});
    } else if ([type isEqualToString:@"ensure_capture"]) {
        ATVVCaptureGate gate = self.captureGate;
        ATVVCaptureAuthorize(&gate);
        self.captureGate = gate;
        self.keepCaptureOpen = YES;
        [self startKeepAliveTimer];
        if (!self.isStreaming) [self openMicrophone];
    } else if ([type isEqualToString:@"stop_capture"]) {
        ATVVCaptureGate gate = self.captureGate;
        ATVVCaptureDisable(&gate);
        self.captureGate = gate;
        self.keepCaptureOpen = NO;
        self.pendingMicrophoneOpen = NO;
        [self.keepAliveTimer invalidate];
        self.keepAliveTimer = nil;
        [self closeMicrophoneForcefully];
    } else if ([type isEqualToString:@"set_escape_cancel"]) {
        BOOL enabled = [message[@"enabled"] boolValue];
        if (self.escapeCancelActive != enabled) {
            self.escapeCancelActive = enabled;
            self.escapeCancelDown = NO;
            BOOL listenConfiguredTrigger = [self.keyboardConfig[@"enabled"] boolValue] || [self.keyboardConfig[@"captureCancelOnly"] boolValue];
            if (enabled) {
                if (!self.eventTap) {
                    [self restartKeyboardTap];
                } else {
                    Emit(@"keyboard_escape_cancel_ready", @{@"enabled": @YES});
                }
            } else {
                if (!listenConfiguredTrigger && !self.appSwitcherActive) {
                    [self teardownKeyboardTap];
                }
            }
        }
        if (!enabled) Emit(@"keyboard_escape_cancel_ready", @{@"enabled": @NO});
    } else if ([type isEqualToString:@"app_switcher_commit"]) {
        [self finishAppSwitcher:YES];
    } else if ([type isEqualToString:@"app_switcher_cancel"]) {
        [self finishAppSwitcher:NO];
    } else if ([type isEqualToString:@"post_key"]) {
        NSString *target = message[@"target"];
        if ([target isEqualToString:@"snapnoteNewNote"]) {
            NSString *actionId = [message[@"actionId"] isKindOfClass:[NSString class]] ? message[@"actionId"] : @"";
            [self prepareSnapNoteAndTriggerGlobalNewNote:actionId shortcut:message[@"shortcut"]];
        } else if ([target isEqualToString:@"appleNotesNewNote"]) {
            NSString *actionId = [message[@"actionId"] isKindOfClass:[NSString class]] ? message[@"actionId"] : @"";
            NSString *tag = [message[@"tag"] isKindOfClass:[NSString class]] ? message[@"tag"] : @"";
            [self prepareAppleNotesAndCreateNewNoteWithActionId:actionId tag:tag];
        } else if ([target isEqualToString:@"typeTextAndEnter"]) {
            NSString *text = message[@"text"];
            [self postStringAndEnter:[text isKindOfClass:[NSString class]] ? text : @""];
        } else if ([target isKindOfClass:[NSString class]]) [self postTarget:target];
        else if ([message[@"keyCode"] respondsToSelector:@selector(integerValue)]) {
            [self postKeyCode:[message[@"keyCode"] unsignedShortValue] modifiers:message[@"modifiers"] ?: @[]];
        }
    } else if ([type isEqualToString:@"choose_file"]) {
        NSString *buttonId = message[@"buttonId"];
        NSString *pickerId = message[@"pickerId"];
        if ([buttonId isKindOfClass:[NSString class]] && [pickerId isKindOfClass:[NSString class]]) {
            [self chooseFileForButton:buttonId pickerId:pickerId];
        }
    } else if ([type isEqualToString:@"scan_remote"]) {
        NSTimeInterval duration = [message[@"duration"] respondsToSelector:@selector(doubleValue)]
            ? [message[@"duration"] doubleValue] : 60.0;
        if (duration < 60.0) duration = 60.0;
        self.scanningEmitted = NO;
        if (self.central.state == CBManagerStatePoweredOn && !self.peripheral) {
            [self startDiscoveryWindowWithDuration:duration];
        }
    } else if ([type isEqualToString:@"shutdown"]) {
        [self shutdown];
    }
}

- (NSArray<NSDictionary *> *)installedApplications {
    NSMutableArray<NSURL *> *roots = [NSMutableArray new];
    for (NSString *path in NSSearchPathForDirectoriesInDomains(NSApplicationDirectory,
            NSLocalDomainMask | NSSystemDomainMask | NSUserDomainMask, YES)) {
        NSURL *url = [NSURL fileURLWithPath:path isDirectory:YES];
        if ([[NSFileManager defaultManager] fileExistsAtPath:url.path]) [roots addObject:url];
    }
    NSURL *coreServicesApps = [NSURL fileURLWithPath:@"/System/Library/CoreServices/Applications" isDirectory:YES];
    if ([[NSFileManager defaultManager] fileExistsAtPath:coreServicesApps.path]) [roots addObject:coreServicesApps];

    NSMutableDictionary<NSString *, NSDictionary *> *byBundleId = [NSMutableDictionary new];
    NSDirectoryEnumerationOptions options = NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants;
    for (NSURL *root in roots) {
        NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
            enumeratorAtURL:root includingPropertiesForKeys:@[NSURLIsDirectoryKey]
            options:options errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
        for (NSURL *url in enumerator) {
            if ([url.pathExtension.lowercaseString isEqualToString:@"app"]) {
                NSBundle *bundle = [NSBundle bundleWithURL:url];
                NSDictionary *info = bundle.infoDictionary ?: @{};
                NSString *bundleId = [info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]] ? info[@"CFBundleIdentifier"] : bundle.bundleIdentifier;
                if (bundleId.length > 0 && bundleId.length <= 255 &&
                    [bundleId rangeOfString:@"[^A-Za-z0-9.-]" options:NSRegularExpressionSearch].location == NSNotFound) {
                    NSString *name = [info[@"CFBundleDisplayName"] isKindOfClass:[NSString class]] ? info[@"CFBundleDisplayName"] : nil;
                    if (name.length == 0) name = [info[@"CFBundleName"] isKindOfClass:[NSString class]] ? info[@"CFBundleName"] : nil;
                    if (name.length == 0) name = url.lastPathComponent.stringByDeletingPathExtension;
                    if (!byBundleId[bundleId]) byBundleId[bundleId] = @{@"bundleId": bundleId, @"name": name};
                }
                [enumerator skipDescendants];
            } else if (enumerator.level >= 5) {
                [enumerator skipDescendants];
            }
        }
    }
    return [[byBundleId allValues] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
}

- (void)chooseFileForButton:(NSString *)buttonId pickerId:(NSString *)pickerId {
    if (self.filePickerOpen) {
        Emit(@"file_picker_error", @{@"buttonId": buttonId, @"pickerId": pickerId, @"message": @"已有一个文件选择窗口打开。"});
        return;
    }
    self.filePickerOpen = YES;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"选择文件";
    panel.message = @"选择遥控器按键要打开的文件";
    [NSApp activateIgnoringOtherApps:YES];
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        self.filePickerOpen = NO;
        if (result == NSModalResponseOK && panel.URL.isFileURL) {
            Emit(@"file_selected", @{@"buttonId": buttonId, @"pickerId": pickerId,
                @"path": panel.URL.path ?: @"", @"name": panel.URL.lastPathComponent ?: @""});
        } else {
            Emit(@"file_picker_cancelled", @{@"buttonId": buttonId, @"pickerId": pickerId});
        }
    }];
}

- (void)startHID {
    if (self.hidManager) return;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    NSDictionary *matching = @{
        [NSString stringWithUTF8String:kIOHIDVendorIDKey]: @(kRemoteVendorID),
        [NSString stringWithUTF8String:kIOHIDProductIDKey]: @(kRemoteProductID)
    };
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)matching);
    void *context = (__bridge void *)self;
    IOHIDManagerRegisterDeviceMatchingCallback(manager, HIDDeviceMatchedCallback, context);
    IOHIDManagerRegisterDeviceRemovalCallback(manager, HIDDeviceRemovedCallback, context);
    IOHIDManagerRegisterInputReportCallback(manager, HIDInputReportCallback, context);
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    IOReturn result = IOHIDManagerOpen(manager, kIOHIDOptionsTypeSeizeDevice);
    if (result == kIOReturnSuccess) {
        self.hidManager = manager;
        Emit(@"hid_listening", @{});
        if ([self refreshHIDDevicePresence]) {
            Emit(@"hid_connected", @{@"vendorId": @(kRemoteVendorID), @"productId": @(kRemoteProductID)});
            if (self.central.state == CBManagerStatePoweredOn && !self.peripheral) {
                [self startDiscoveryWindowWithDuration:15.0];
            }
        }
    } else {
        Log([NSString stringWithFormat:@"IOHIDManagerOpen failed: 0x%08X", (uint32_t)result]);
        Emit(@"permission_required", @{@"permission": @"input-monitoring"});
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        CFRelease(manager);
    }
}

- (void)stopHID {
    if (!self.hidManager) return;
    IOHIDManagerUnscheduleFromRunLoop(self.hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    IOHIDManagerClose(self.hidManager, kIOHIDOptionsTypeNone);
    CFRelease(self.hidManager);
    self.hidManager = NULL;
    self.hidDevicePresent = NO;
    self.lastUsage = nil;
    Emit(@"hid_disabled", @{});
}

- (BOOL)refreshHIDDevicePresence {
    if (!self.hidManager) {
        self.hidDevicePresent = NO;
        return NO;
    }
    CFSetRef devices = IOHIDManagerCopyDevices(self.hidManager);
    CFIndex count = devices ? CFSetGetCount(devices) : 0;
    if (devices) CFRelease(devices);
    self.hidDevicePresent = (count > 0);
    return self.hidDevicePresent;
}

- (void)releasePeripheralForSystemPairingIfNeeded {
    if (self.central.isScanning) {
        [self.central stopScan];
    }
    if (self.peripheral) {
        CBPeripheral *current = self.peripheral;
        [self resetATVVState];
        self.peripheral = nil;
        [self.central cancelPeripheralConnection:current];
        Emit(@"ble_disconnected", @{@"message": @""});
    }
}

- (void)scheduleHIDPresenceGuardForPeripheral:(CBPeripheral *)peripheral {
    __weak RemoteHelper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || helper.peripheral != peripheral) return;
        if (![helper refreshHIDDevicePresence]) {
            [helper releasePeripheralForSystemPairingIfNeeded];
        }
    });
}

- (void)handleReportID:(uint32_t)reportID data:(NSData *)data {
    self.hidDevicePresent = YES;
    if (!self.peripheral && !self.connectAttemptPending && !self.discoveryTimer && !self.stopped && self.central.state == CBManagerStatePoweredOn) {
        [self startDiscoveryWindowWithDuration:15.0];
    }
    if (reportID != 0x01 || data.length == 0) return;
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = bytes[0] == (uint8_t)reportID ? 1 : 0;
    if (offset >= data.length) return;
    uint8_t usage = bytes[offset];
    if (usage == 0) {
        if (self.lastUsage) {
            Emit(@"button_up", @{@"buttonId": self.lastUsage});
            self.lastUsage = nil;
        }
        return;
    }
    NSString *buttonID = [NSString stringWithFormat:@"%02X", usage];
    if ([self.lastUsage isEqualToString:buttonID]) return;
    if (self.lastUsage) Emit(@"button_up", @{@"buttonId": self.lastUsage});
    self.lastUsage = buttonID;
    Emit(@"button_down", @{@"buttonId": buttonID});
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    switch (central.state) {
        case CBManagerStatePoweredOn:
            Emit(@"bluetooth_ready", @{});
            [self discoverRemote];
            break;
        case CBManagerStateUnauthorized:
            Emit(@"permission_required", @{@"permission": @"bluetooth"});
            break;
        case CBManagerStatePoweredOff:
            [self stopDiscoveryTimer];
            self.scanningEmitted = NO;
            [central stopScan];
            [self.keepAliveTimer invalidate];
            self.keepAliveTimer = nil;
            self.keepCaptureOpen = NO;
            [self resetATVVState];
            self.peripheral = nil;
            Emit(@"bluetooth_off", @{});
            break;
        case CBManagerStateUnsupported:
            Emit(@"unsupported_platform", @{});
            break;
        default:
            break;
    }
}

- (void)startDiscoveryTimer {
    if (self.stopped || self.central.state != CBManagerStatePoweredOn || self.peripheral) {
        [self stopDiscoveryTimer];
        return;
    }
    if (self.discoveryTimer) return;
    __weak RemoteHelper *weakSelf = self;
    self.discoveryTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *timer) {
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || helper.central.state != CBManagerStatePoweredOn || helper.peripheral) {
            [helper stopDiscoveryTimer];
            return;
        }
        [helper pollOrScanForRemote];
    }];
}

- (void)stopDiscoveryTimer {
    [self.discoveryTimer invalidate];
    self.discoveryTimer = nil;
    [self.discoveryWindowTimer invalidate];
    self.discoveryWindowTimer = nil;
}

- (CBPeripheral *)retrieveKnownChromecastPeripheral {
    NSString *savedUUIDString = [[NSUserDefaults standardUserDefaults] stringForKey:kLastChromecastPeripheralUUIDKey];
    if (savedUUIDString.length == 0) return nil;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:savedUUIDString];
    if (!uuid) return nil;
    NSArray<CBPeripheral *> *peripherals = [self.central retrievePeripheralsWithIdentifiers:@[uuid]];
    for (CBPeripheral *candidate in peripherals) {
        if (candidate.name.length == 0 || [self isChromecastRemote:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (void)rememberChromecastPeripheral:(CBPeripheral *)peripheral {
    NSString *uuidString = peripheral.identifier.UUIDString;
    if (uuidString.length > 0) {
        [[NSUserDefaults standardUserDefaults] setObject:uuidString forKey:kLastChromecastPeripheralUUIDKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)discoverRemote {
    NSString *savedUUID = [[NSUserDefaults standardUserDefaults] stringForKey:kLastChromecastPeripheralUUIDKey];
    NSTimeInterval initialDuration = (savedUUID.length > 0) ? 15.0 : 60.0;
    [self startDiscoveryWindowWithDuration:initialDuration];
}

- (void)startDiscoveryWindowWithDuration:(NSTimeInterval)duration {
    if (self.stopped || self.central.state != CBManagerStatePoweredOn || self.peripheral) {
        [self stopDiscoveryTimer];
        return;
    }
    if (duration <= 0) duration = 15.0;
    [self pollOrScanForRemote];
    if (self.peripheral) return;

    [self startDiscoveryTimer];
    [self.discoveryWindowTimer invalidate];
    __weak RemoteHelper *weakSelf = self;
    self.discoveryWindowTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(NSTimer *timer) {
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || helper.peripheral) return;
        [helper stopDiscoveryTimer];
        if (helper.central.isScanning) [helper.central stopScan];
        helper.scanningEmitted = NO;
        Emit(@"remote_standby", @{});
    }];
}

- (void)pollOrScanForRemote {
    if (self.stopped || self.central.state != CBManagerStatePoweredOn || self.peripheral) return;
    if (![self refreshHIDDevicePresence]) {
        if (self.central.isScanning) [self.central stopScan];
        if (!self.scanningEmitted) {
            self.scanningEmitted = YES;
            Emit(@"scanning", @{});
        }
        return;
    }
    CBUUID *atvvService = [CBUUID UUIDWithString:ATVVServiceUUID];
    CBUUID *hidService = [CBUUID UUIDWithString:@"1812"];
    NSArray<CBUUID *> *queryServices = @[
        atvvService,
        hidService,
        [CBUUID UUIDWithString:@"180A"],
        [CBUUID UUIDWithString:@"180F"],
        [CBUUID UUIDWithString:@"1800"]
    ];
    NSArray<CBPeripheral *> *connected = [self.central retrieveConnectedPeripheralsWithServices:queryServices];
    CBPeripheral *matched = nil;
    for (CBPeripheral *candidate in connected) {
        if ([self isChromecastRemote:candidate]) {
            matched = candidate;
            break;
        }
    }
    if (!matched) {
        CBPeripheral *known = [self retrieveKnownChromecastPeripheral];
        if (known) {
            matched = known;
        }
    }
    if (matched) {
        [self stopDiscoveryTimer];
        if (self.central.isScanning) [self.central stopScan];
        self.scanningEmitted = NO;
        [self connectPeripheral:matched];
        return;
    }
    if (!self.central.isScanning) {
        [self.central scanForPeripheralsWithServices:@[atvvService, hidService]
                                             options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
    }
    if (!self.scanningEmitted) {
        self.scanningEmitted = YES;
        Emit(@"scanning", @{});
    }
}

- (BOOL)isChromecastRemote:(CBPeripheral *)peripheral {
    return [peripheral.name localizedCaseInsensitiveContainsString:@"Chromecast Remote"];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    if (![self refreshHIDDevicePresence]) {
        [central stopScan];
        return;
    }
    NSString *advertisedName = [advertisementData[CBAdvertisementDataLocalNameKey] isKindOfClass:[NSString class]]
        ? advertisementData[CBAdvertisementDataLocalNameKey] : @"";
    BOOL matchesName = [self isChromecastRemote:peripheral] ||
        [advertisedName localizedCaseInsensitiveContainsString:@"Chromecast Remote"];
    if (self.stopped || self.peripheral || !matchesName) return;
    [self stopDiscoveryTimer];
    self.scanningEmitted = NO;
    [central stopScan];
    [self connectPeripheral:peripheral];
}

- (void)resetATVVState {
    ATVVCaptureGate gate = self.captureGate;
    ATVVCaptureDisable(&gate);
    self.captureGate = gate;
    self.keepCaptureOpen = NO;
    [self.keepAliveTimer invalidate];
    self.keepAliveTimer = nil;
    self.capabilityHandshakeGeneration++;
    self.connectAttemptGeneration++;
    self.connectAttemptPending = NO;
    self.capabilityRequestOutstanding = NO;
    self.audioNotificationReady = NO;
    self.controlNotificationReady = NO;
    self.commandCharacteristic = nil;
    self.audioCharacteristic = nil;
    self.controlCharacteristic = nil;
    self.capsVersion = 0;
    self.codec = 0;
    self.frameSize = 0;
    self.streamID = 0;
    self.sequence = 0;
    self.predictor = 0;
    self.stepIndex = 0;
    self.isStreaming = NO;
    self.voiceButtonPressed = NO;
    self.pendingMicrophoneOpen = NO;
    self.hasPendingSyncBeforeStart = NO;
    self.previous8kSample = nil;
}

- (void)connectPeripheral:(CBPeripheral *)peripheral {
    if (![self refreshHIDDevicePresence]) {
        [self releasePeripheralForSystemPairingIfNeeded];
        return;
    }
    if (self.peripheral == peripheral) return;
    [self stopDiscoveryTimer];
    self.scanningEmitted = NO;
    if (self.peripheral) [self.central cancelPeripheralConnection:self.peripheral];
    [self resetATVVState];
    self.peripheral = peripheral;
    peripheral.delegate = self;
    if (peripheral.state == CBPeripheralStateConnected) {
        self.connectAttemptPending = NO;
        self.connectAttemptGeneration++;
        self.scanRetryCount = 0;
        [self rememberChromecastPeripheral:peripheral];
        [self scheduleHIDPresenceGuardForPeripheral:peripheral];
        Emit(@"ble_connected", @{@"name": peripheral.name ?: @"Chromecast Voice Remote"});
        [peripheral discoverServices:@[[CBUUID UUIDWithString:ATVVServiceUUID]]];
        return;
    }
    self.connectAttemptPending = YES;
    NSUInteger generation = ++self.connectAttemptGeneration;
    [self.central connectPeripheral:peripheral options:nil];
    [self scheduleHIDPresenceGuardForPeripheral:peripheral];
    Emit(@"connecting", @{@"name": peripheral.name ?: @"Chromecast Voice Remote"});
    __weak RemoteHelper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || !helper.connectAttemptPending ||
            helper.connectAttemptGeneration != generation || helper.peripheral != peripheral) return;
        helper.connectAttemptPending = NO;
        Emit(@"device_error", @{@"message": @"Bluetooth connection timed out; retrying"});
        [helper.central cancelPeripheralConnection:peripheral];
        helper.peripheral = nil;
        [helper resetATVVState];
        [helper retryScan];
    });
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    if (peripheral != self.peripheral || self.stopped) return;
    if (![self refreshHIDDevicePresence]) {
        [self releasePeripheralForSystemPairingIfNeeded];
        return;
    }
    self.connectAttemptPending = NO;
    self.connectAttemptGeneration++;
    self.scanRetryCount = 0;
    [self rememberChromecastPeripheral:peripheral];
    [self scheduleHIDPresenceGuardForPeripheral:peripheral];
    Emit(@"ble_connected", @{@"name": peripheral.name ?: @"Chromecast Voice Remote"});
    [peripheral discoverServices:@[[CBUUID UUIDWithString:ATVVServiceUUID]]];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    if (peripheral != self.peripheral) return;
    [self resetATVVState];
    Emit(@"device_error", @{@"message": error.localizedDescription ?: @"Bluetooth connection failed"});
    self.peripheral = nil;
    [self retryScan];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
    if (peripheral != self.peripheral) return;
    [self.keepAliveTimer invalidate];
    self.keepAliveTimer = nil;
    self.keepCaptureOpen = NO;
    [self resetATVVState];
    self.peripheral = nil;
    Emit(@"ble_disconnected", @{@"message": error.localizedDescription ?: @""});
    if (!self.stopped) [self retryScan];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (peripheral != self.peripheral) return;
    CBUUID *target = [CBUUID UUIDWithString:ATVVServiceUUID];
    CBService *service = nil;
    for (CBService *candidate in peripheral.services) {
        if ([candidate.UUID isEqual:target]) { service = candidate; break; }
    }
    if (error || !service) {
        [self failCurrentPeripheral:error.localizedDescription ?: @"ATVV service was not found after connection"];
        return;
    }
    [peripheral discoverCharacteristics:@[
        [CBUUID UUIDWithString:ATVVCommandUUID],
        [CBUUID UUIDWithString:ATVVAudioUUID],
        [CBUUID UUIDWithString:ATVVControlUUID]
    ] forService:service];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    if (peripheral != self.peripheral) return;
    if (error) {
        [self failCurrentPeripheral:error.localizedDescription ?: @"ATVV characteristic discovery failed"];
        return;
    }
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSString *uuid = characteristic.UUID.UUIDString.uppercaseString;
        if ([uuid isEqualToString:ATVVCommandUUID]) {
            self.commandCharacteristic = characteristic;
            if (characteristic.properties & (CBCharacteristicPropertyNotify | CBCharacteristicPropertyIndicate)) {
                [peripheral setNotifyValue:YES forCharacteristic:characteristic];
            }
        } else if ([uuid isEqualToString:ATVVAudioUUID]) {
            self.audioCharacteristic = characteristic;
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        } else if ([uuid isEqualToString:ATVVControlUUID]) {
            self.controlCharacteristic = characteristic;
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }
    }
    if (!self.commandCharacteristic || !self.audioCharacteristic || !self.controlCharacteristic) {
        [self failCurrentPeripheral:@"ATVV command/audio/control characteristics are incomplete"];
        return;
    }
    self.audioNotificationReady = self.audioCharacteristic.isNotifying;
    self.controlNotificationReady = self.controlCharacteristic.isNotifying;
    NSUInteger generation = ++self.capabilityHandshakeGeneration;
    __weak RemoteHelper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || helper.capabilityHandshakeGeneration != generation || helper.capsVersion != 0) return;
        [helper failCurrentPeripheral:@"ATVV notifications or capability negotiation timed out; reconnecting to the remote"];
    });
    [self requestCapabilitiesIfReady];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (peripheral != self.peripheral) return;
    if (error) {
        [self failCurrentPeripheral:error.localizedDescription ?: @"ATVV notification setup failed"];
        return;
    }
    if (characteristic == self.audioCharacteristic) self.audioNotificationReady = characteristic.isNotifying;
    if (characteristic == self.controlCharacteristic) self.controlNotificationReady = characteristic.isNotifying;
    [self requestCapabilitiesIfReady];
}

- (void)requestCapabilitiesIfReady {
    if (self.stopped || self.capabilityRequestOutstanding || self.capsVersion != 0 ||
        !self.peripheral || !self.commandCharacteristic || !self.audioNotificationReady || !self.controlNotificationReady) return;
    self.capabilityRequestOutstanding = YES;
    [self writeCommand:[NSData dataWithBytes:(uint8_t[]){0x0A,0x01,0x00,0x00,0x03,0x03} length:6]];
}

- (void)failCurrentPeripheral:(NSString *)message {
    Emit(@"device_error", @{@"message": message ?: @"ATVV connection failed"});
    if (self.peripheral) [self.central cancelPeripheralConnection:self.peripheral];
    else [self retryScan];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    if (peripheral != self.peripheral) return;
    if (error || characteristic.value.length == 0) {
        if (error) Emit(@"device_error", @{@"message": error.localizedDescription ?: @"Bluetooth notification failed"});
        return;
    }
    NSString *uuid = characteristic.UUID.UUIDString.uppercaseString;
    if ([uuid isEqualToString:ATVVAudioUUID]) [self decodeAudio:characteristic.value];
    else [self handleControl:characteristic.value];
}

- (void)handleControl:(NSData *)data {
    if (data.length == 0) return;
    const uint8_t *b = data.bytes;
    switch (b[0]) {
        case 0x00: {
            self.isStreaming = NO;
            self.pendingMicrophoneOpen = NO;
            uint8_t reason = data.length > 1 ? b[1] : 0;
            if (self.voiceButtonPressed) {
                self.voiceButtonPressed = NO;
                Emit(@"voice_release", @{@"reason": @(reason)});
            }
            Emit(@"audio_stop", @{@"reason": @(reason)});
            if (self.keepCaptureOpen) {
                Emit(@"audio_reopen_requested", @{@"reason": @(reason), @"frames": @(self.audioFrameCount)});
                [self openMicrophone];
            } else {
                [self.keepAliveTimer invalidate];
                self.keepAliveTimer = nil;
                Emit(@"audio_stream_stopped", @{@"reason": @(reason), @"frames": @(self.audioFrameCount)});
            }
            self.audioFrameCount = 0;
            break;
        }
        case 0x04: {
            if (data.length < 2) return;
            uint8_t reason = b[1];
            if (self.capsVersion == 0x0100 && data.length >= 4) {
                self.codec = b[2];
                self.streamID = b[3];
            }
            self.isStreaming = YES;
            self.audioFrameCount = 0;
            // A remote can start directly without START_SEARCH. Wait briefly
            // for the app to authorize a real voice session.
            [self armCaptureProbe:@"audio_start"];
            if (self.keepCaptureOpen) [self startKeepAliveTimer];
            if (!self.hasPendingSyncBeforeStart) {
                self.sequence = 0;
                self.predictor = 0;
                self.stepIndex = 0;
            }
            self.hasPendingSyncBeforeStart = NO;
            self.previous8kSample = nil;
            if (reason == 0x03) {
                self.voiceButtonPressed = YES;
                Emit(@"voice_press", @{@"reason": @(reason)});
            }
            Emit(@"audio_start", @{
                @"reason": @(reason),
                @"streamId": @(self.streamID),
                @"sampleRate": @(self.codec == 0x02 ? 16000 : 8000)
            });
            break;
        }
        case 0x08:
            Emit(@"start_search", @{});
            // This may be the physical voice-key path. Preserve MIC_OPEN, but
            // never allow an unconfirmed search probe to keep capture alive.
            BOOL newProbe = [self armCaptureProbe:@"start_search"];
            if (!self.isStreaming && (self.keepCaptureOpen || newProbe)) [self openMicrophone];
            break;
        case 0x0A:
            if (self.capsVersion == 0x0100 && data.length >= 7) {
                self.codec = b[1];
                self.sequence = (uint16_t)b[2] << 8 | b[3];
                self.predictor = (int16_t)((uint16_t)b[4] << 8 | b[5]);
                self.stepIndex = MIN(88, b[6]);
                self.hasPendingSyncBeforeStart = !self.isStreaming;
                self.previous8kSample = nil;
                Emit(@"audio_sync", @{@"sequence": @(self.sequence), @"sampleRate": @(self.codec == 0x02 ? 16000 : 8000)});
            }
            break;
        case 0x0B:
            [self parseCapabilities:data];
            break;
        case 0x0C: {
            NSUInteger code = data.length >= 3 ? ((NSUInteger)b[1] << 8) | b[2] : 65535;
            Emit(@"mic_open_error", @{@"code": @(code)});
            break;
        }
        default:
            break;
    }
}

- (void)parseCapabilities:(NSData *)data {
    if (data.length < 3) return;
    const uint8_t *b = data.bytes;
    uint16_t version = (uint16_t)b[1] << 8 | b[2];
    uint8_t codecs = 0;
    if (version == 0x0004 && data.length >= 9) {
        self.capsVersion = 0x0004;
        codecs = b[4];
        self.frameSize = (uint16_t)b[5] << 8 | b[6];
    } else if (version == 0x0100 && data.length >= 7) {
        self.capsVersion = 0x0100;
        codecs = b[3];
        self.frameSize = (uint16_t)b[5] << 8 | b[6];
    } else {
        [self failCurrentPeripheral:@"Unsupported ATVV protocol version"];
        return;
    }
    if (codecs & 0x02) self.codec = 0x02;
    else if (codecs & 0x01) self.codec = 0x01;
    else {
        self.capsVersion = 0;
        [self failCurrentPeripheral:@"Remote does not advertise supported ADPCM codecs"];
        return;
    }
    self.predictor = 0;
    self.stepIndex = 0;
    self.sequence = 0;
    self.capabilityRequestOutstanding = NO;
    self.capabilityHandshakeGeneration++;
    Emit(@"device_ready", @{
        @"protocolVersion": self.capsVersion == 0x0100 ? @"1.0" : @"0.4",
        @"sampleRate": @(self.codec == 0x02 ? 16000 : 8000),
        @"frameSize": @(self.frameSize)
    });
    if (self.pendingMicrophoneOpen || self.keepCaptureOpen) [self openMicrophone];
}

- (NSArray<NSNumber *> *)decodeBytes:(NSData *)data {
    NSMutableArray<NSNumber *> *output = [NSMutableArray arrayWithCapacity:data.length * 2];
    const uint8_t *bytes = data.bytes;
    ATVVADPCMState state = {(int32_t)self.predictor, (int)self.stepIndex};
    for (NSUInteger i = 0; i < data.length; i++) {
        [output addObject:@(ATVVADPCMDecodeNibble((bytes[i] >> 4) & 0x0F, &state))];
        [output addObject:@(ATVVADPCMDecodeNibble(bytes[i] & 0x0F, &state))];
    }
    self.predictor = state.predictor;
    self.stepIndex = state.stepIndex;
    return output;
}

- (void)decodeAudio:(NSData *)data {
    if (!self.isStreaming || self.codec == 0) return;
    self.audioFrameCount++;
    if (self.audioFrameCount == 1 || self.audioFrameCount % 100 == 0) {
        Emit(@"audio_stream_progress", @{@"frames": @(self.audioFrameCount), @"bytes": @(data.length)});
    }
    NSArray<NSNumber *> *samples = nil;
    uint16_t frameSequence = self.sequence;
    if (self.capsVersion == 0x0004) {
        if (data.length != self.frameSize || data.length < 6) return;
        const uint8_t *b = data.bytes;
        frameSequence = (uint16_t)b[0] << 8 | b[1];
        self.predictor = (int16_t)((uint16_t)b[3] << 8 | b[4]);
        self.stepIndex = MIN(88, b[5]);
        NSMutableArray<NSNumber *> *frame = [NSMutableArray arrayWithObject:@((int16_t)self.predictor)];
        NSData *payload = [data subdataWithRange:NSMakeRange(6, data.length - 6)];
        [frame addObjectsFromArray:[self decodeBytes:payload]];
        samples = frame;
    } else {
        samples = [self decodeBytes:data];
        self.sequence++;
    }
    [self emitPCMSamples:samples sequence:frameSequence inputRate:(self.codec == 0x02 ? 16000 : 8000)];
}

- (void)emitPCMSamples:(NSArray<NSNumber *> *)samples sequence:(uint16_t)sequence inputRate:(NSInteger)inputRate {
    ATVVCaptureGate gate = self.captureGate;
    if (samples.count == 0 || !ATVVCaptureMayEmit(&gate)) return;
    NSMutableArray<NSNumber *> *output = [NSMutableArray arrayWithCapacity:inputRate == 8000 ? samples.count * 2 : samples.count];
    if (inputRate == 16000) {
        [output addObjectsFromArray:samples];
    } else {
        NSMutableData *inputData = [NSMutableData dataWithLength:samples.count * sizeof(int16_t)];
        int16_t *input = inputData.mutableBytes;
        for (NSUInteger i = 0; i < samples.count; i++) input[i] = (int16_t)samples[i].shortValue;
        NSMutableData *outputData = [NSMutableData dataWithLength:samples.count * 2 * sizeof(int16_t)];
        int16_t previous = self.previous8kSample ? self.previous8kSample.shortValue : 0;
        bool hasPrevious = self.previous8kSample != nil;
        size_t outputCount = ATVVUpsampleLinear8k(input, samples.count, outputData.mutableBytes, &previous, &hasPrevious);
        self.previous8kSample = hasPrevious ? @(previous) : nil;
        const int16_t *upsampled = outputData.bytes;
        for (size_t i = 0; i < outputCount; i++) [output addObject:@(upsampled[i])];
    }
    NSMutableData *pcm = [NSMutableData dataWithLength:output.count * 2];
    uint8_t *bytes = pcm.mutableBytes;
    for (NSUInteger i = 0; i < output.count; i++) {
        uint16_t bits = (uint16_t)(int16_t)output[i].shortValue;
        bytes[i * 2] = (uint8_t)(bits & 0xFF);
        bytes[i * 2 + 1] = (uint8_t)((bits >> 8) & 0xFF);
    }
    Emit(@"audio_frame", @{
        @"sequence": @(sequence),
        @"sampleRate": @16000,
        @"pcmBase64": [pcm base64EncodedStringWithOptions:0]
    });
}

// A short provisional opening preserves the legacy 0x08/physical-key path.
// No PCM is emitted before ensure_capture. If the app never authorizes it,
// force a stop; stale timers are invalidated by generation on stop/reconnect.
- (BOOL)armCaptureProbe:(NSString *)origin {
    ATVVCaptureGate gate = self.captureGate;
    uint64_t token = 0;
    if (!ATVVCaptureBeginProbe(&gate, &token)) return NO;
    self.captureGate = gate;
    Emit(@"capture_probe_started", @{@"origin": origin ?: @"unknown", @"timeoutMs": @2000});
    __weak RemoteHelper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped) return;
        ATVVCaptureGate current = helper.captureGate;
        if (!ATVVCaptureExpireProbe(&current, token)) return;
        helper.captureGate = current;
        helper.keepCaptureOpen = NO;
        helper.pendingMicrophoneOpen = NO;
        [helper.keepAliveTimer invalidate];
        helper.keepAliveTimer = nil;
        [helper closeMicrophoneForcefully];
        helper.isStreaming = NO;
        Emit(@"capture_probe_timeout", @{@"message": @"Remote capture stopped: the application did not authorize a voice session."});
        Emit(@"mic_open_error", @{@"message": @"Voice session authorization timed out.", @"code": @0});
    });
    return YES;
}

- (void)openMicrophone {
    if (!self.commandCharacteristic || !self.peripheral || self.capsVersion == 0 || self.codec == 0) {
        self.pendingMicrophoneOpen = YES;
        Log(@"ATVV microphone request deferred until capability negotiation completes.");
        return;
    }
    if (self.isStreaming) return;
    self.pendingMicrophoneOpen = NO;
    self.predictor = 0;
    self.stepIndex = 0;
    self.sequence = 0;
    self.previous8kSample = nil;
    uint8_t bytesV04[] = {0x0C, 0x00, (uint8_t)self.codec};
    uint8_t bytesV10[] = {0x0C, 0x00};
    NSData *command = self.capsVersion == 0x0004
        ? [NSData dataWithBytes:bytesV04 length:sizeof(bytesV04)]
        : [NSData dataWithBytes:bytesV10 length:sizeof(bytesV10)];
    [self writeCommand:command];
    Emit(@"mic_open_requested", @{});
}

- (void)closeMicrophoneForcefully {
    self.pendingMicrophoneOpen = NO;
    if (!self.commandCharacteristic) return;
    uint8_t bytesV04[] = {0x0D};
    uint8_t bytesV10[] = {0x0D, self.streamID};
    NSData *command = self.capsVersion == 0x0004
        ? [NSData dataWithBytes:bytesV04 length:sizeof(bytesV04)]
        : [NSData dataWithBytes:bytesV10 length:sizeof(bytesV10)];
    [self writeCommand:command];
    self.isStreaming = NO;
    Emit(@"audio_closed", @{});
    Emit(@"mic_close_requested", @{});
}

- (void)writeCommand:(NSData *)data {
    if (!self.peripheral || !self.commandCharacteristic) return;
    CBCharacteristicWriteType type = (self.commandCharacteristic.properties & CBCharacteristicPropertyWrite)
        ? CBCharacteristicWriteWithResponse
        : CBCharacteristicWriteWithoutResponse;
    [self.peripheral writeValue:data forCharacteristic:self.commandCharacteristic type:type];
}

- (void)startKeepAliveTimer {
    if (self.keepAliveTimer) return;
    __weak RemoteHelper *weakSelf = self;
    self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:4.0 repeats:YES block:^(NSTimer *timer) {
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || !helper.keepCaptureOpen) {
            [timer invalidate];
            if (helper.keepAliveTimer == timer) helper.keepAliveTimer = nil;
            return;
        }
        if (!helper.isStreaming || helper.capsVersion == 0) return;
        if (helper.capsVersion == 0x0004) {
            uint8_t b[] = {0x0C, 0x00, (uint8_t)helper.codec};
            [helper writeCommand:[NSData dataWithBytes:b length:sizeof(b)]];
        } else {
            uint8_t b[] = {0x0E, helper.streamID};
            [helper writeCommand:[NSData dataWithBytes:b length:sizeof(b)]];
        }
    }];
}

- (void)retryScan {
    if (self.stopped || self.central.state != CBManagerStatePoweredOn || self.peripheral) return;
    self.scanRetryScheduled = NO;
    self.scanRetryCount = 0;
    self.scanningEmitted = NO;
    [self startDiscoveryWindowWithDuration:6.0];
}

- (uint16_t)keyCodeForName:(NSString *)name {
    NSString *upper = name.uppercaseString;
    NSDictionary<NSString *, NSNumber *> *functions = @{
        @"F1": @0x7A, @"F2": @0x78, @"F3": @0x63, @"F4": @0x76,
        @"F5": @0x60, @"F6": @0x61, @"F7": @0x62, @"F8": @0x64,
        @"F9": @0x65, @"F10": @0x6D, @"F11": @0x67, @"F12": @0x6F
    };
    if (functions[upper]) return functions[upper].unsignedShortValue;
    NSDictionary<NSString *, NSNumber *> *letters = @{
        @"A": @0x00, @"B": @0x0B, @"C": @0x08, @"D": @0x02, @"E": @0x0E,
        @"F": @0x03, @"G": @0x05, @"H": @0x04, @"I": @0x22, @"J": @0x26,
        @"K": @0x28, @"L": @0x25, @"M": @0x2E, @"N": @0x2D, @"O": @0x1F,
        @"P": @0x23, @"Q": @0x0C, @"R": @0x0F, @"S": @0x01, @"T": @0x11,
        @"U": @0x20, @"V": @0x09, @"W": @0x0D, @"X": @0x07, @"Y": @0x10, @"Z": @0x06
    };
    if (letters[upper]) return letters[upper].unsignedShortValue;
    NSDictionary<NSString *, NSNumber *> *digits = @{
        @"0": @0x1D, @"1": @0x12, @"2": @0x13, @"3": @0x14, @"4": @0x15,
        @"5": @0x17, @"6": @0x16, @"7": @0x1A, @"8": @0x1C, @"9": @0x19
    };
    if (digits[upper]) return digits[upper].unsignedShortValue;
    NSDictionary<NSString *, NSNumber *> *other = @{
        @"SPACE": @0x31, @"RETURN": @0x24, @"ESCAPE": @0x35,
        @"TAB": @0x30, @"BACKSPACE": @0x33, @"FORWARDDELETE": @0x75,
        @"HOME": @0x73, @"END": @0x77, @"PAGEUP": @0x74, @"PAGEDOWN": @0x79,
        @"ARROWUP": @0x7E, @"ARROWDOWN": @0x7D, @"ARROWLEFT": @0x7B, @"ARROWRIGHT": @0x7C,
        @"LEFTCOMMAND": @0x37, @"RIGHTCOMMAND": @0x36,
        @"LEFTOPTION": @0x3A, @"RIGHTOPTION": @0x3D,
        @"LEFTCONTROL": @0x3B, @"RIGHTCONTROL": @0x3E,
        @"LEFTSHIFT": @0x38, @"RIGHTSHIFT": @0x3C,
        @"FN": @0x3F
    };
    return other[upper] ? other[upper].unsignedShortValue : UINT16_MAX;
}

- (BOOL)isModifierTriggerKey:(NSString *)key {
    static NSSet<NSString *> *modifierKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        modifierKeys = [NSSet setWithArray:@[
            @"LeftCommand", @"RightCommand", @"LeftOption", @"RightOption",
            @"LeftControl", @"RightControl", @"LeftShift", @"RightShift", @"Fn"
        ]];
    });
    return [modifierKeys containsObject:key];
}

- (CGEventFlags)flagsForModifiers:(NSArray<NSString *> *)modifiers {
    CGEventFlags flags = 0;
    for (NSString *name in modifiers) {
        NSString *modifier = name.lowercaseString;
        if ([modifier isEqualToString:@"command"] || [modifier isEqualToString:@"cmd"]) flags |= kCGEventFlagMaskCommand;
        else if ([modifier isEqualToString:@"option"] || [modifier isEqualToString:@"alt"]) flags |= kCGEventFlagMaskAlternate;
        else if ([modifier isEqualToString:@"control"] || [modifier isEqualToString:@"ctrl"]) flags |= kCGEventFlagMaskControl;
        else if ([modifier isEqualToString:@"shift"]) flags |= kCGEventFlagMaskShift;
        else if ([modifier isEqualToString:@"fn"]) flags |= kCGEventFlagMaskSecondaryFn;
    }
    return flags;
}

- (void)teardownKeyboardTap {
    [self stopTapOrderGuard];
    if (self.eventTap) {
        CGEventTapEnable(self.eventTap, false);
        CFMachPortInvalidate(self.eventTap);
    }
    if (self.eventTapSource) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), self.eventTapSource, kCFRunLoopCommonModes);
        CFRelease(self.eventTapSource);
        self.eventTapSource = NULL;
    }
    if (self.eventTap) {
        CFRelease(self.eventTap);
        self.eventTap = NULL;
    }
}

- (void)restartKeyboardTap {
    if (self.keyboardTriggerDown) Emit(@"keyboard_trigger_up", @{@"interrupted": @YES, @"passThrough": @([self.keyboardConfig[@"passThrough"] boolValue])});
    [self teardownKeyboardTap];
    self.keyboardTriggerDown = NO;
    self.keyboardModifierState = (KKModifierState){0};
    self.escapeCancelDown = NO;
    BOOL captureCancelOnly = [self.keyboardConfig[@"captureCancelOnly"] boolValue];
    BOOL keyboardTriggerEnabled = [self.keyboardConfig[@"enabled"] boolValue];
    BOOL listenConfiguredTrigger = keyboardTriggerEnabled || captureCancelOnly;
    if (!listenConfiguredTrigger && !self.escapeCancelActive && !self.appSwitcherActive) return;
    NSString *key = captureCancelOnly ? @"Escape" : (self.keyboardConfig[@"key"] ?: @"Fn");
    if (listenConfiguredTrigger && [self keyCodeForName:key] == UINT16_MAX) {
        Emit(@"keyboard_trigger_error", @{@"message": @"Unsupported keyboard shortcut key"});
        return;
    }
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown)
        | CGEventMaskBit(kCGEventKeyUp)
        | CGEventMaskBit(kCGEventFlagsChanged);
    self.eventTap = CGEventTapCreate(
        kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        mask, KeyboardEventCallback, (__bridge void *)self
    );
    if (!self.eventTap) {
        self.eventTap = CGEventTapCreate(
            kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
            mask, KeyboardEventCallback, (__bridge void *)self
        );
    }
    if (!self.eventTap) {
        NSString *source = self.appSwitcherActive ? @"app-switcher" :
            self.escapeCancelActive ? @"escape-cancel" : @"keyboard-trigger";
        Emit(@"permission_required", @{
            @"permission": @"accessibility",
            @"source": source,
            @"message": @"请在系统设置的隐私与安全性中，允许 KKvoice Remote Helper 使用辅助功能。"
        });
        return;
    }
    self.eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, self.eventTap, 0);
    if (self.eventTapSource) {
        CFRunLoopAddSource(CFRunLoopGetMain(), self.eventTapSource, kCFRunLoopCommonModes);
        CGEventTapEnable(self.eventTap, true);
        [self startTapOrderGuard];
        if (listenConfiguredTrigger) {
            Emit(@"keyboard_trigger_ready", @{@"key": key, @"captureCancelOnly": @(captureCancelOnly), @"passThrough": @([self.keyboardConfig[@"passThrough"] boolValue])});
        }
        if (self.escapeCancelActive) Emit(@"keyboard_escape_cancel_ready", @{@"enabled": @YES});
    } else {
        [self teardownKeyboardTap];
    }
}

- (void)handleWorkspaceApplicationDeactivated:(NSNotification *)notification {
    if (self.stopped || !self.eventTap) return;
    if (self.keyboardTriggerDown || self.escapeCancelDown || self.appSwitcherActive) return;
    NSRunningApplication *deactivatedApp = notification.userInfo[NSWorkspaceApplicationKey];
    NSString *bundleId = deactivatedApp.bundleIdentifier.lowercaseString ?: @"";
    if ([bundleId hasPrefix:@"com.bytedance.inputmethod.doubaoime"]) {
        [self restartKeyboardTap];
    }
}

- (void)startTapOrderGuard {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self
                                                                  name:NSWorkspaceDidDeactivateApplicationNotification
                                                                object:nil];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(handleWorkspaceApplicationDeactivated:)
                                                               name:NSWorkspaceDidDeactivateApplicationNotification
                                                             object:nil];
}

- (void)stopTapOrderGuard {
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self
                                                                  name:NSWorkspaceDidDeactivateApplicationNotification
                                                                object:nil];
}

- (BOOL)handleKeyboardType:(CGEventType)type event:(CGEventRef)event {
    int64_t syntheticMarker = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
    if (syntheticMarker == kSyntheticKeyMarker || syntheticMarker == kKKvoiceSyntheticKeyMarker) return NO;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (self.keyboardTriggerDown) Emit(@"keyboard_trigger_up", @{@"interrupted": @YES, @"passThrough": @([self.keyboardConfig[@"passThrough"] boolValue])});
        self.keyboardTriggerDown = NO;
        self.escapeCancelDown = NO;
        self.keyboardModifierState = (KKModifierState){0};
        if (self.eventTap) {
            CGEventTapEnable(self.eventTap, true);
            Emit(@"keyboard_tap_reenabled", @{});
        }
        return NO;
    }
    uint16_t eventKeyCode = (uint16_t)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    uint16_t escapeKeyCode = [self keyCodeForName:@"Escape"];
    if (self.appSwitcherEscapeDown && type == kCGEventKeyUp && eventKeyCode == escapeKeyCode) {
        self.appSwitcherEscapeDown = NO;
        return YES;
    }
    if (self.appSwitcherActive && eventKeyCode == escapeKeyCode) {
        if (type == kCGEventKeyDown) {
            if (!self.appSwitcherEscapeDown) {
                self.appSwitcherEscapeDown = YES;
                [self finishAppSwitcher:NO];
            }
            return YES;
        }
        if (type == kCGEventKeyUp) {
            BOOL consumeRelease = self.appSwitcherEscapeDown;
            self.appSwitcherEscapeDown = NO;
            return consumeRelease;
        }
    }
    if (self.escapeCancelActive &&
        eventKeyCode == escapeKeyCode) {
        if (type == kCGEventKeyDown) {
            if (!self.escapeCancelDown) {
                self.escapeCancelDown = YES;
                Emit(@"keyboard_cancel_session", @{});
            }
            return NO;
        }
        if (type == kCGEventKeyUp) {
            self.escapeCancelDown = NO;
            return NO;
        }
    }
    if ([self.keyboardConfig[@"captureCancelOnly"] boolValue]) {
        if (CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) != [self keyCodeForName:@"Escape"]) return NO;
        if (type == kCGEventKeyDown) {
            if (!self.keyboardTriggerDown) {
                self.keyboardTriggerDown = YES;
                Emit(@"keyboard_capture_cancel", @{});
            }
            return YES;
        }
        if (type == kCGEventKeyUp) {
            BOOL consumeRelease = self.keyboardTriggerDown;
            self.keyboardTriggerDown = NO;
            return consumeRelease;
        }
        return NO;
    }
    if (![self.keyboardConfig[@"enabled"] boolValue]) return NO;
    BOOL passThrough = [self.keyboardConfig[@"passThrough"] boolValue];
    NSString *key = self.keyboardConfig[@"key"] ?: @"Fn";
    uint16_t code = [self keyCodeForName:key];
    if (code == UINT16_MAX || CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode) != code) return NO;
    if ([self isModifierTriggerKey:key]) {
        KKModifierEvent edgeEvent;
        if (type == kCGEventFlagsChanged) edgeEvent = KKFlagsChanged;
        else if (type == kCGEventKeyDown) edgeEvent = KKKeyDown;
        else if (type == kCGEventKeyUp) edgeEvent = KKKeyUp;
        else return NO;
        KKModifierState modifierState = self.keyboardModifierState;
        KKModifierEdge edge = KKModifierObserve(&modifierState, code, eventKeyCode, edgeEvent,
            CGEventGetFlags(event), false,
            CGEventGetIntegerValueField(event, kCGKeyboardEventAutorepeat) != 0);
        self.keyboardModifierState = modifierState;
        if (edge == KKModifierNone) return passThrough ? NO : self.keyboardTriggerDown;
        if (edge == KKModifierUp) {
            BOOL wasDown = self.keyboardTriggerDown;
            if (wasDown) Emit(@"keyboard_trigger_up", @{@"passThrough": @(passThrough)});
            self.keyboardTriggerDown = NO;
            return wasDown && !passThrough;
        }
        self.keyboardTriggerDown = YES;
        Emit(@"keyboard_trigger_down", @{@"passThrough": @(passThrough)});
        return !passThrough;
    }
    if (type == kCGEventKeyUp) {
        BOOL wasDown = self.keyboardTriggerDown;
        if (wasDown) Emit(@"keyboard_trigger_up", @{@"passThrough": @(passThrough)});
        self.keyboardTriggerDown = NO;
        return wasDown && !passThrough;
    }
    if (type != kCGEventKeyDown) return NO;
    NSArray<NSString *> *modifiers = self.keyboardConfig[@"modifiers"] ?: @[];
    CGEventFlags expected = [self flagsForModifiers:modifiers];
    CGEventFlags actual = CGEventGetFlags(event);
    if (expected != 0 && (actual & expected) != expected) return NO;
    if (self.keyboardTriggerDown) return !passThrough;
    self.keyboardTriggerDown = YES;
    Emit(@"keyboard_trigger_down", @{@"passThrough": @(passThrough)});
    return !passThrough;
}

- (void)postKeyCode:(uint16_t)keyCode keyDown:(BOOL)down flags:(CGEventFlags)flags {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, down);
    if (!event) return;
    CGEventSetFlags(event, flags);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kSyntheticKeyMarker);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

- (void)postKeyCode:(uint16_t)keyCode modifiers:(NSArray<NSString *> *)modifiers {
    CGEventFlags flags = [self flagsForModifiers:modifiers];
    for (NSNumber *down in @[@YES, @NO]) {
        [self postKeyCode:keyCode keyDown:down.boolValue flags:flags];
    }
}

- (void)postKeyCodeWithoutText:(uint16_t)keyCode keyDown:(BOOL)down flags:(CGEventFlags)flags {
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)keyCode, down);
    if (!event) return;
    CGEventSetFlags(event, flags);
    // Keep the physical keycode and modifier state for shortcut matching, but
    // explicitly clear translated text on the printable L down/up events.
    CGEventKeyboardSetUnicodeString(event, 0, NULL);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, kSyntheticKeyMarker);
    CGEventPost(kCGHIDEventTap, event);
    CFRelease(event);
}

- (void)postOptionLShortcutWithoutText {
    CGEventFlags optionFlags = kCGEventFlagMaskAlternate;

    // Reproduce the same state transitions as a physical Option+L chord. Merely
    // setting the Option flag on L does not send an Option key-down/up event,
    // which can make some app frameworks treat L as ordinary text instead of
    // dispatching the registered shortcut.
    [self postKeyCode:0x3A keyDown:YES flags:optionFlags];
    [self postKeyCodeWithoutText:0x25 keyDown:YES flags:optionFlags];
    [self postKeyCodeWithoutText:0x25 keyDown:NO flags:optionFlags];
    [self postKeyCode:0x3A keyDown:NO flags:0];
}

- (BOOL)postUnicodeChunk:(NSString *)chunk {
    if (chunk.length == 0) return YES;
    CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, 0, true);
    CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, 0, false);
    if (!keyDown || !keyUp) {
        if (keyDown) CFRelease(keyDown);
        if (keyUp) CFRelease(keyUp);
        return NO;
    }
    UniChar unicodeUnits[16];
    [chunk getCharacters:unicodeUnits range:NSMakeRange(0, chunk.length)];
    CGEventKeyboardSetUnicodeString(keyDown, (UniCharCount)chunk.length, unicodeUnits);
    CGEventSetIntegerValueField(keyDown, kCGEventSourceUserData, kSyntheticKeyMarker);
    CGEventSetIntegerValueField(keyUp, kCGEventSourceUserData, kSyntheticKeyMarker);
    CGEventPost(kCGHIDEventTap, keyDown);
    CGEventPost(kCGHIDEventTap, keyUp);
    CFRelease(keyDown);
    CFRelease(keyUp);
    return YES;
}

- (BOOL)resolvePrintableASCIICharacter:(UniChar)character
                                layout:(const UCKeyboardLayout *)layout
                               keyCode:(uint16_t *)keyCode
                                 flags:(CGEventFlags *)flags {
    const struct {
        UInt32 carbonModifiers;
        CGEventFlags eventFlags;
    } modifierSets[] = {
        {0, 0},
        {(UInt32)((shiftKey >> 8) & 0xFF), kCGEventFlagMaskShift},
        {(UInt32)((optionKey >> 8) & 0xFF), kCGEventFlagMaskAlternate},
        {(UInt32)(((shiftKey | optionKey) >> 8) & 0xFF), kCGEventFlagMaskShift | kCGEventFlagMaskAlternate}
    };

    for (NSUInteger modifierIndex = 0; modifierIndex < sizeof(modifierSets) / sizeof(modifierSets[0]); modifierIndex++) {
        for (UInt16 candidate = 0; candidate < 128; candidate++) {
            UInt32 deadKeyState = 0;
            UniChar translated[8] = {0};
            UniCharCount translatedLength = 0;
            OSStatus status = UCKeyTranslate(
                layout,
                candidate,
                kUCKeyActionDown,
                modifierSets[modifierIndex].carbonModifiers,
                LMGetKbdType(),
                0,
                &deadKeyState,
                sizeof(translated) / sizeof(translated[0]),
                &translatedLength,
                translated
            );
            if (status != noErr || deadKeyState != 0 || translatedLength != 1 || translated[0] != character) continue;
            if (keyCode) *keyCode = candidate;
            if (flags) *flags = modifierSets[modifierIndex].eventFlags;
            return YES;
        }
    }
    return NO;
}

- (NSArray<NSDictionary *> *)physicalKeyStrokesForASCIIText:(NSString *)text {
    TISInputSourceRef inputSource = TISCopyCurrentKeyboardLayoutInputSource();
    if (!inputSource) return nil;
    CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData);
    if (!layoutData || CFDataGetLength(layoutData) < (CFIndex)sizeof(UCKeyboardLayout)) {
        CFRelease(inputSource);
        return nil;
    }
    const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
    if (!layout) {
        CFRelease(inputSource);
        return nil;
    }

    NSMutableArray<NSDictionary *> *strokes = [NSMutableArray arrayWithCapacity:text.length];
    for (NSUInteger index = 0; index < text.length; index++) {
        UniChar character = [text characterAtIndex:index];
        if (character < 0x20 || character > 0x7E) {
            CFRelease(inputSource);
            return nil;
        }
        uint16_t keyCode = 0;
        CGEventFlags flags = 0;
        if (![self resolvePrintableASCIICharacter:character layout:layout keyCode:&keyCode flags:&flags]) {
            CFRelease(inputSource);
            return nil;
        }
        [strokes addObject:@{@"keyCode": @(keyCode), @"flags": @(flags)}];
    }
    CFRelease(inputSource);
    return strokes;
}

- (void)postPhysicalKeyStroke:(NSDictionary *)stroke {
    uint16_t keyCode = [stroke[@"keyCode"] unsignedShortValue];
    CGEventFlags flags = [stroke[@"flags"] unsignedLongLongValue];
    BOOL shift = (flags & kCGEventFlagMaskShift) != 0;
    BOOL option = (flags & kCGEventFlagMaskAlternate) != 0;

    if (shift) [self postKeyCode:0x38 keyDown:YES flags:kCGEventFlagMaskShift];
    if (option) [self postKeyCode:0x3A keyDown:YES flags:(shift ? kCGEventFlagMaskShift : 0) | kCGEventFlagMaskAlternate];
    [self postKeyCode:keyCode keyDown:YES flags:flags];
    [self postKeyCode:keyCode keyDown:NO flags:flags];
    if (option) [self postKeyCode:0x3A keyDown:NO flags:shift ? kCGEventFlagMaskShift : 0];
    if (shift) [self postKeyCode:0x38 keyDown:NO flags:0];
    usleep(5000);
}

- (void)postStringAndEnter:(NSString *)text {
    if (text.length == 0) {
        Emit(@"action_error", @{@"message": @"此按键没有设置要输入的字符串。"});
        return;
    }
    NSMutableCharacterSet *lineOrControlCharacters = [[NSCharacterSet controlCharacterSet] mutableCopy];
    [lineOrControlCharacters formUnionWithCharacterSet:[NSCharacterSet newlineCharacterSet]];
    if (text.length > 128 || [text rangeOfCharacterFromSet:lineOrControlCharacters].location != NSNotFound) {
        Emit(@"action_error", @{@"message": @"字符串最多 128 个字符，且不能包含换行或控制字符。"});
        return;
    }
    NSArray<NSDictionary *> *physicalStrokes = [self physicalKeyStrokesForASCIIText:text];
    if (physicalStrokes) {
        for (NSDictionary *stroke in physicalStrokes) [self postPhysicalKeyStroke:stroke];
    } else {
        NSUInteger offset = 0;
        while (offset < text.length) {
            NSUInteger chunkLength = MIN((NSUInteger)16, text.length - offset);
            if (offset + chunkLength < text.length) {
                unichar last = [text characterAtIndex:offset + chunkLength - 1];
                unichar next = [text characterAtIndex:offset + chunkLength];
                BOOL splitsSurrogatePair = last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF;
                if (splitsSurrogatePair) chunkLength--;
            }
            NSString *chunk = [text substringWithRange:NSMakeRange(offset, chunkLength)];
            if (![self postUnicodeChunk:chunk]) {
                Emit(@"action_error", @{@"message": @"无法发送输入字符串。"});
                return;
            }
            offset += chunkLength;
        }
    }
    usleep(50000);
    [self postKeyCode:0x24 modifiers:@[]];
    Emit(@"action_done", @{});
}

- (void)restartAppSwitcherTimeout {
    NSUInteger generation = ++self.appSwitcherGeneration;
    __weak RemoteHelper *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RemoteHelper *helper = weakSelf;
        if (!helper || helper.stopped || !helper.appSwitcherActive || helper.appSwitcherGeneration != generation) return;
        [helper finishAppSwitcher:NO];
    });
}

- (void)beginAppSwitcherWithDirection:(NSInteger)direction {
    if (self.appSwitcherActive) return;
    self.appSwitcherActive = YES;
    self.appSwitcherEscapeDown = NO;
    [self restartKeyboardTap];
    [self postKeyCode:0x37 keyDown:YES flags:kCGEventFlagMaskCommand];
    self.appSwitcherCommandDown = YES;
    NSArray<NSString *> *modifiers = direction < 0 ? @[@"command", @"shift"] : @[@"command"];
    [self postKeyCode:0x30 modifiers:modifiers];
    Emit(@"app_switcher_state", @{@"active": @YES, @"escapeCancelAvailable": @(self.eventTap != NULL)});
    [self restartAppSwitcherTimeout];
}

- (void)beginAppSwitcher {
    [self beginAppSwitcherWithDirection:0];
}

- (void)finishAppSwitcher:(BOOL)commit {
    if (!self.appSwitcherActive) return;
    if (!commit) [self postKeyCode:0x35 modifiers:@[@"command"]];
    if (self.appSwitcherCommandDown) {
        [self postKeyCode:0x37 keyDown:NO flags:0];
        self.appSwitcherCommandDown = NO;
    }
    self.appSwitcherActive = NO;
    self.appSwitcherGeneration++;
    Emit(@"app_switcher_state", @{@"active": @NO, @"escapeCancelAvailable": @NO});
    if (!self.stopped) {
        __weak RemoteHelper *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            RemoteHelper *helper = weakSelf;
            if (helper && !helper.stopped) [helper restartKeyboardTap];
        });
    }
}

- (void)postTarget:(NSString *)target {
    if ([target isEqualToString:@"appSwitcher"]) {
        [self beginAppSwitcher];
        return;
    }
    if ([target isEqualToString:@"appSwitcherLeft"] || [target isEqualToString:@"appSwitcherRight"]) {
        if (!self.appSwitcherActive) {
            [self beginAppSwitcherWithDirection:[target isEqualToString:@"appSwitcherLeft"] ? -1 : 1];
        } else {
            uint16_t keyCode = [target isEqualToString:@"appSwitcherLeft"] ? 0x7B : 0x7C;
            [self postKeyCode:keyCode modifiers:@[@"command"]];
            [self restartAppSwitcherTimeout];
        }
        return;
    }
    if (self.appSwitcherActive && [target isEqualToString:@"arrowLeft"]) {
        [self postKeyCode:0x7B modifiers:@[@"command"]];
        [self restartAppSwitcherTimeout];
        return;
    }
    if (self.appSwitcherActive && [target isEqualToString:@"arrowRight"]) {
        [self postKeyCode:0x7C modifiers:@[@"command"]];
        [self restartAppSwitcherTimeout];
        return;
    }
    if (self.appSwitcherActive) return;
    BOOL focusMainChatAfterLaunch = [target hasPrefix:@"openAppFocus:"];
    if (focusMainChatAfterLaunch || [target hasPrefix:@"openApp:"]) {
        NSString *prefix = focusMainChatAfterLaunch ? @"openAppFocus:" : @"openApp:";
        NSString *bundleId = [target substringFromIndex:prefix.length];
        if (focusMainChatAfterLaunch &&
            ![@[@"com.openai.codex", @"com.openai.chatgpt"] containsObject:bundleId]) {
            Emit(@"action_error", @{@"message": @"⌥+L 聚焦只支持 ChatGPT App。"});
            return;
        }
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSURL *appURL = [workspace URLForApplicationWithBundleIdentifier:bundleId];
        if (!appURL) {
            Emit(@"action_error", @{@"message": [NSString stringWithFormat:@"找不到应用 %@。请重新选择应用。", bundleId]});
            return;
        }
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.activates = YES;
        [workspace openApplicationAtURL:appURL configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
            if (error) Emit(@"action_error", @{@"message": [NSString stringWithFormat:@"打开应用失败：%@", error.localizedDescription ?: bundleId]});
            else if (focusMainChatAfterLaunch) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self sendFocusMainChatShortcutToApplication:bundleId attempt:0];
                });
            } else Emit(@"action_done", @{});
        }];
        return;
    }
    if ([target hasPrefix:@"openFile:"]) {
        NSString *path = [target substringFromIndex:@"openFile:".length];
        BOOL isDirectory = NO;
        if (![path hasPrefix:@"/"] || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            Emit(@"action_error", @{@"message": [NSString stringWithFormat:@"文件不存在或不是文件：%@", path.lastPathComponent ?: path]});
            return;
        }
        NSURL *url = [NSURL fileURLWithPath:path];
        if (![[NSWorkspace sharedWorkspace] openURL:url]) {
            Emit(@"action_error", @{@"message": [NSString stringWithFormat:@"无法打开文件：%@", path.lastPathComponent ?: path]});
        } else Emit(@"action_done", @{});
        return;
    }
    if ([target hasPrefix:@"key:"]) {
        uint16_t keyCode = [self keyCodeForName:[target substringFromIndex:4]];
        if (keyCode != UINT16_MAX) [self postKeyCode:keyCode modifiers:@[]];
        return;
    }
    if ([target hasPrefix:@"shortcut:"]) {
        NSArray<NSString *> *parts = [target componentsSeparatedByString:@":"];
        if (parts.count == 3) {
            uint16_t keyCode = [self keyCodeForName:parts[2]];
            NSArray<NSString *> *modifiers = [parts[1] isEqualToString:@"none"]
                ? @[] : [parts[1] componentsSeparatedByString:@"+"];
            if (keyCode != UINT16_MAX) [self postKeyCode:keyCode modifiers:modifiers];
        }
        return;
    }
    NSDictionary<NSString *, NSArray *> *targets = @{
        @"arrowUp": @[@0x7E, @[]], @"arrowDown": @[@0x7D, @[]],
        @"arrowLeft": @[@0x7B, @[]], @"arrowRight": @[@0x7C, @[]],
        @"return": @[@0x24, @[]], @"escape": @[@0x35, @[]],
        @"delete": @[@0x33, @[]], @"tab": @[@0x30, @[]], @"space": @[@0x31, @[]],
        @"home": @[@0x73, @[]], @"end": @[@0x77, @[]], @"pageUp": @[@0x74, @[]],
        @"pageDown": @[@0x79, @[]], @"showDesktop": @[@0x67, @[@"fn"]],
        @"lockScreen": @[@0x0C, @[@"control", @"command"]],
        @"commandSpace": @[@0x31, @[@"command"]], @"commandA": @[@0x00, @[@"command"]],
        @"commandC": @[@0x08, @[@"command"]], @"commandV": @[@0x09, @[@"command"]],
        @"commandZ": @[@0x06, @[@"command"]], @"commandS": @[@0x01, @[@"command"]],
        @"commandW": @[@0x0D, @[@"command"]], @"commandQ": @[@0x0C, @[@"command"]],
        @"F1": @[@0x7A, @[]], @"F2": @[@0x78, @[]], @"F3": @[@0x63, @[]],
        @"F4": @[@0x76, @[]], @"F5": @[@0x60, @[]], @"F6": @[@0x61, @[]],
        @"F7": @[@0x62, @[]], @"F8": @[@0x64, @[]], @"F9": @[@0x65, @[]],
        @"F10": @[@0x6D, @[]], @"F11": @[@0x67, @[]], @"F12": @[@0x6F, @[]]
    };
    NSArray *item = targets[target];
    if (item.count == 2) {
        [self postKeyCode:[item[0] unsignedShortValue] modifiers:item[1]];
        return;
    }
    if ([target isEqualToString:@"volumeUp"] || [target isEqualToString:@"volumeDown"] || [target isEqualToString:@"mute"]) {
        int32_t key = [target isEqualToString:@"volumeUp"] ? 0 : [target isEqualToString:@"volumeDown"] ? 1 : 7;
        int32_t states[] = {0xA, 0xB};
        for (NSUInteger i = 0; i < 2; i++) {
            int32_t state = states[i];
            int data1 = (key << 16) | (state << 8);
            NSEvent *event = [NSEvent otherEventWithType:NSEventTypeSystemDefined
                location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
                subtype:8 data1:data1 data2:-1];
            CGEventRef cgEvent = event.CGEvent;
            if (cgEvent) CGEventPost(kCGHIDEventTap, cgEvent);
        }
    }
}

- (void)sendFocusMainChatShortcutToApplication:(NSString *)bundleId attempt:(NSUInteger)attempt {
    if (self.stopped) return;
    NSRunningApplication *frontmost = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (![frontmost.bundleIdentifier isEqualToString:bundleId]) {
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self sendFocusMainChatShortcutToApplication:bundleId attempt:attempt + 1];
            });
        } else {
            Emit(@"action_error", @{@"message": @"ChatGPT 未切到前台，未发送 ⌥+L。"});
        }
        return;
    }
    [self postOptionLShortcutWithoutText];
    Emit(@"action_done", @{@"message": @"已向 ChatGPT 发送 ⌥+L。"});
}

- (void)prepareSnapNoteAndTriggerGlobalNewNote:(NSString *)actionId shortcut:(NSString *)shortcut {
    if (actionId.length == 0 || ![shortcut isKindOfClass:[NSString class]] || ![shortcut hasPrefix:@"shortcut:"]) {
        Emit(@"action_error", @{@"message": @"闪念笔记动作缺少请求标识。"});
        return;
    }
    if (self.snapnotePendingActionId) {
        Emit(@"action_error", @{@"actionId": actionId, @"message": @"已有闪念笔记动作正在执行。"});
        return;
    }
    self.snapnotePendingActionId = actionId;
    self.snapnoteShortcutSent = NO;
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *appURL = [workspace URLForApplicationWithBundleIdentifier:@"com.geekholt.snapnote"];
    if (!appURL) {
        self.snapnotePendingActionId = nil;
        Emit(@"action_error", @{@"actionId": actionId, @"message": @"找不到闪念笔记 App。"});
        return;
    }
    NSRunningApplication *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.geekholt.snapnote"].firstObject;
    if (running) {
        [self sendSnapNoteGlobalNewNoteShortcutWithActionId:actionId shortcut:shortcut attempt:0];
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [workspace openApplicationAtURL:appURL configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped || ![self.snapnotePendingActionId isEqualToString:actionId]) return;
            if (error || !application) {
                self.snapnotePendingActionId = nil;
                Emit(@"action_error", @{@"actionId": actionId, @"message": @"无法启动闪念笔记 App。"});
                return;
            }
            [self sendSnapNoteGlobalNewNoteShortcutWithActionId:actionId shortcut:shortcut attempt:0];
        });
    }];
}

- (void)sendSnapNoteGlobalNewNoteShortcutWithActionId:(NSString *)actionId shortcut:(NSString *)shortcut attempt:(NSUInteger)attempt {
    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:actionId]) return;
    NSRunningApplication *snapNote = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.geekholt.snapnote"].firstObject;
    if (!snapNote || !snapNote.isFinishedLaunching) {
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self sendSnapNoteGlobalNewNoteShortcutWithActionId:actionId shortcut:shortcut attempt:attempt + 1];
            });
        } else {
            self.snapnotePendingActionId = nil;
            Emit(@"action_error", @{@"actionId": actionId, @"message": @"闪念笔记未完成启动，未发送所设快捷键。"});
        }
        return;
    }
    // Re-check before the side effect; the method and cancellation execute on
    // the same main queue, so cancellation cannot interleave this sequence.
    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:actionId]) return;
    self.snapnoteShortcutSent = YES;
    [self postSnapNoteGlobalNewNoteShortcut:shortcut];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self completeSnapNoteNewNoteActionWithActionId:actionId];
    });
}

- (void)postSnapNoteGlobalNewNoteShortcut:(NSString *)shortcut {
    NSArray *parts = [shortcut componentsSeparatedByString:@":"];
    if (parts.count != 3) return;
    NSArray *modifiers = [parts[1] componentsSeparatedByString:@"+"];
    NSDictionary *codes = @{@"command": @0x37, @"option": @0x3A, @"control": @0x3B, @"shift": @0x38, @"fn": @0x3F};
    CGEventFlags flags = 0;
    NSMutableArray *pressed = [NSMutableArray new];
    for (NSString *modifier in modifiers) {
        NSNumber *code = codes[modifier];
        if (!code) continue;
        flags |= [self flagsForModifiers:@[modifier]];
        [self postKeyCode:code.unsignedShortValue keyDown:YES flags:flags];
        [pressed addObject:modifier];
    }
    uint16_t keyCode = [self keyCodeForName:parts[2]];
    [self postKeyCodeWithoutText:keyCode keyDown:YES flags:flags];
    [self postKeyCodeWithoutText:keyCode keyDown:NO flags:flags];
    for (NSString *modifier in pressed.reverseObjectEnumerator) {
        flags &= ~[self flagsForModifiers:@[modifier]];
        [self postKeyCode:[codes[modifier] unsignedShortValue] keyDown:NO flags:flags];
    }
}

- (void)completeSnapNoteNewNoteActionWithActionId:(NSString *)actionId {
    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:actionId]) return;
    self.snapnotePendingActionId = nil;
    self.snapnoteShortcutSent = NO;
    NSRunningApplication *frontmost = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (![frontmost.bundleIdentifier isEqualToString:@"com.geekholt.snapnote"]) {
        Emit(@"action_error", @{@"actionId": actionId, @"message": @"闪念笔记没有保持在前台，插件未继续处理。"});
        return;
    }
    if (![self postUnicodeChunk:@"."]) {
        Emit(@"action_error", @{@"actionId": actionId, @"message": @"无法输入句点，未继续添加标签。"});
        return;
    }
    Emit(@"action_done", @{@"actionId": actionId, @"message": @"已输入句点；等待本机接口核对新笔记。"});
}

- (void)prepareAppleNotesAndCreateNewNoteWithActionId:(NSString *)actionId tag:(NSString *)tag {
    if (self.snapnotePendingActionId) {
        NSMutableDictionary *payload = [@{@"message": @"已有笔记动作正在执行。"} mutableCopy];
        if (actionId.length > 0) payload[@"actionId"] = actionId;
        Emit(@"action_error", payload);
        return;
    }
    NSString *effectiveActionId = actionId.length > 0 ? actionId : [NSUUID UUID].UUIDString.lowercaseString;
    self.snapnotePendingActionId = effectiveActionId;
    self.snapnoteShortcutSent = NO;

    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSURL *appURL = [workspace URLForApplicationWithBundleIdentifier:@"com.apple.Notes"];
    if (!appURL) {
        NSURL *fallbackURL = [NSURL fileURLWithPath:@"/System/Applications/Notes.app" isDirectory:YES];
        if ([[NSFileManager defaultManager] fileExistsAtPath:fallbackURL.path]) {
            appURL = fallbackURL;
        }
    }
    if (!appURL) {
        self.snapnotePendingActionId = nil;
        NSMutableDictionary *payload = [@{@"message": @"找不到系统备忘录 App。"} mutableCopy];
        if (actionId.length > 0) payload[@"actionId"] = actionId;
        Emit(@"action_error", payload);
        return;
    }

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [workspace openApplicationAtURL:appURL configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped || ![self.snapnotePendingActionId isEqualToString:effectiveActionId]) return;
            if (error || !application) {
                self.snapnotePendingActionId = nil;
                NSMutableDictionary *payload = [@{@"message": @"无法启动系统备忘录 App。"} mutableCopy];
                if (actionId.length > 0) payload[@"actionId"] = actionId;
                Emit(@"action_error", payload);
                return;
            }
            [self waitForAppleNotesFrontmostAndSendNewNoteWithActionId:effectiveActionId
                                                      originalActionId:actionId
                                                                   tag:tag
                                                               attempt:0];
        });
    }];
}

- (void)waitForAppleNotesFrontmostAndSendNewNoteWithActionId:(NSString *)effectiveActionId
                                            originalActionId:(NSString *)originalActionId
                                                         tag:(NSString *)tag
                                                     attempt:(NSUInteger)attempt {
    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:effectiveActionId]) return;
    NSRunningApplication *notesApp = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Notes"].firstObject;
    NSRunningApplication *frontmost = [NSWorkspace sharedWorkspace].frontmostApplication;
    BOOL isFrontmost = notesApp && notesApp.isFinishedLaunching && [frontmost.bundleIdentifier isEqualToString:@"com.apple.Notes"];
    if (!isFrontmost) {
        if (notesApp && (attempt == 0 || attempt == 5)) {
            [notesApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
        if (attempt < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self waitForAppleNotesFrontmostAndSendNewNoteWithActionId:effectiveActionId
                                                          originalActionId:originalActionId
                                                                       tag:tag
                                                                   attempt:attempt + 1];
            });
        } else {
            self.snapnotePendingActionId = nil;
            NSMutableDictionary *payload = [@{@"message": @"备忘录未切到前台，未发送新建快捷键。"} mutableCopy];
            if (originalActionId.length > 0) payload[@"actionId"] = originalActionId;
            Emit(@"action_error", payload);
        }
        return;
    }

    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:effectiveActionId]) return;
    self.snapnoteShortcutSent = YES;
    [self postSnapNoteGlobalNewNoteShortcut:@"shortcut:command:N"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self completeAppleNotesNewNoteWithActionId:effectiveActionId originalActionId:originalActionId tag:tag];
    });
}

- (void)completeAppleNotesNewNoteWithActionId:(NSString *)effectiveActionId
                             originalActionId:(NSString *)originalActionId
                                          tag:(NSString *)tag {
    if (self.stopped || ![self.snapnotePendingActionId isEqualToString:effectiveActionId]) return;
    self.snapnotePendingActionId = nil;
    self.snapnoteShortcutSent = NO;

    NSRunningApplication *frontmost = [NSWorkspace sharedWorkspace].frontmostApplication;
    if (![frontmost.bundleIdentifier isEqualToString:@"com.apple.Notes"]) {
        NSMutableDictionary *payload = [@{@"message": @"备忘录没有保持在前台，未写入标签。"} mutableCopy];
        if (originalActionId.length > 0) payload[@"actionId"] = originalActionId;
        Emit(@"action_error", payload);
        return;
    }

    NSString *cleanTag = [tag isKindOfClass:[NSString class]]
        ? [tag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
        : @"";
    while ([cleanTag hasPrefix:@"#"]) {
        cleanTag = [[cleanTag substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    if (cleanTag.length > 0) {
        NSString *tagText = [NSString stringWithFormat:@"#%@ ", cleanTag];
        NSUInteger offset = 0;
        while (offset < tagText.length) {
            NSUInteger chunkLength = MIN((NSUInteger)16, tagText.length - offset);
            if (offset + chunkLength < tagText.length) {
                unichar last = [tagText characterAtIndex:offset + chunkLength - 1];
                unichar next = [tagText characterAtIndex:offset + chunkLength];
                BOOL splitsSurrogatePair = last >= 0xD800 && last <= 0xDBFF && next >= 0xDC00 && next <= 0xDFFF;
                if (splitsSurrogatePair) chunkLength--;
            }
            NSString *chunk = [tagText substringWithRange:NSMakeRange(offset, chunkLength)];
            if (![self postUnicodeChunk:chunk]) {
                NSMutableDictionary *payload = [@{@"message": @"无法在备忘录中输入标签。"} mutableCopy];
                if (originalActionId.length > 0) payload[@"actionId"] = originalActionId;
                Emit(@"action_error", payload);
                return;
            }
            offset += chunkLength;
        }
        usleep(30000);
        [self postKeyCode:0x24 modifiers:@[]];
    }

    NSMutableDictionary *payload = [@{@"message": @"已新建备忘录并添加标签。"} mutableCopy];
    if (originalActionId.length > 0) payload[@"actionId"] = originalActionId;
    Emit(@"action_done", payload);
}

- (void)shutdown {
    if (self.stopped) return;
    self.stopped = YES;
    if (self.appSwitcherActive) [self finishAppSwitcher:NO];
    self.keepCaptureOpen = NO;
    ATVVCaptureGate gate = self.captureGate;
    ATVVCaptureDisable(&gate);
    self.captureGate = gate;
    [self.keepAliveTimer invalidate];
    self.keepAliveTimer = nil;
    [self stopDiscoveryTimer];
    self.scanningEmitted = NO;
    [self closeMicrophoneForcefully];
    [self.central stopScan];
    if (self.peripheral) [self.central cancelPeripheralConnection:self.peripheral];
    [self teardownKeyboardTap];
    [self stopHID];
    Emit(@"helper_stopped", @{});
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

@end

int main(void) {
    @autoreleasepool {
        gOutputLock = [NSObject new];
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        RemoteHelper *helper = [RemoteHelper new];
        [helper start];
        [NSApp run];
    }
    return 0;
}
