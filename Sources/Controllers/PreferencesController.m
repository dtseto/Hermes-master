#import <SPMediaKeyTap/SPMediaKeyTap.h>

#import "PlaybackController.h"
#import "PreferencesController.h"
#import "URLConnection.h"

@interface PreferencesController () {
  NSInteger lastEnabledProxy;
}
@end

@implementation PreferencesController

- (void)awakeFromNib {
  [super awakeFromNib];
  lastEnabledProxy = PREF_KEY_INT(ENABLED_PROXY);

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proxyServerValidityChanged:) name:URLConnectionProxyValidityChangedNotification object:nil];
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
  /* See HermesAppDelegate#updateStatusBarIcon */
  [window setCanHide:NO];

  if (PREF_KEY_BOOL(STATUS_BAR_ICON_BW))
    statusItemShowBlackAndWhiteIcon.state = NSControlStateValueOn;
  else if (PREF_KEY_BOOL(STATUS_BAR_ICON_ALBUM))
    statusItemShowAlbumArt.state = NSControlStateValueOn;
  else
    statusItemShowColorIcon.state = NSControlStateValueOn;

  NSString *last = PREF_KEY_VALUE(LAST_PREF_PANE);
  if (NSClassFromString(@"NSUserNotification") != nil) {
    [notificationEnabled setTitle:@""];
    [notificationType setHidden:NO];
  }

  if (itemIdentifiers == nil) {
    itemIdentifiers = [[toolbar items] valueForKey:@"itemIdentifier"];
  }

  if ([last isEqual:@"playback"]) {
    [toolbar setSelectedItemIdentifier:@"playback"];
    [self setPreferenceView:playback as:@"playback"];
  } else if ([last isEqual:@"network"]) {
    [toolbar setSelectedItemIdentifier:@"network"];
    [self setPreferenceView:network as:@"network"];
  } else {
    [toolbar setSelectedItemIdentifier:@"general"];
    [self setPreferenceView:general as:@"general"];
  }
}

- (void) setPreferenceView:(NSView*) view as:(NSString*)name {
  NSView *container = [window contentView];
  if ([[container subviews] count] > 0) {
    NSView *prev_view = [container subviews][0];
    if (prev_view == view) {
      return;
    }
    [prev_view removeFromSuperviewWithoutNeedingDisplay];
  }

  NSRect frame = [view bounds];
  frame.origin.y = NSHeight([container frame]) - NSHeight([view bounds]);
  [view setFrame:frame];
  [view setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
  [container addSubview:view];
  [window setInitialFirstResponder:view];

  NSRect windowFrame = [window frame];
  NSRect contentRect = [window contentRectForFrameRect:windowFrame];
  windowFrame.size.height = NSHeight(frame) + NSHeight(windowFrame) - NSHeight(contentRect);
  windowFrame.size.width = NSWidth(frame);
  windowFrame.origin.y = NSMaxY([window frame]) - NSHeight(windowFrame);
  [window setFrame:windowFrame display:YES animate:YES];

  NSUInteger toolbarItemIndex = [itemIdentifiers indexOfObject:name];
  NSString *title = @"Preferences";
  if (toolbarItemIndex != NSNotFound) {
    title = [[toolbar items][toolbarItemIndex] label];
  }
  [window setTitle:title];

  if ([HMSAppDelegate playback].mediaKeyTap == nil) {
    mediaKeysCheckbox.enabled = NO;
#ifndef MPREMOTECOMMANDCENTER_MEDIA_KEYS_BROKEN
    if ([HMSAppDelegate playback].remoteCommandCenter != nil) {
      mediaKeysCheckbox.integerValue = YES;
      mediaKeysLabel.stringValue = @"Play/pause and next track keys are always enabled in macOS 10.12.2 and later.";
    } else {
#endif
#if DEBUG
      mediaKeysLabel.stringValue = @"Media keys are not available because this version of Hermes is compiled in debug mode.";
#else
      mediaKeysLabel.stringValue = @"Media keys are unavailable for an unknown reason.";
#endif
#ifndef MPREMOTECOMMANDCENTER_MEDIA_KEYS_BROKEN
    }
#endif
  } else if (@available(macOS 10.15, *)) {
    if (![[HMSAppDelegate playback] hasInputMonitoringAccess]) {
      if (!PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED)) {
        mediaKeysLabel.stringValue = @"Input Monitoring reminder is turned off. Click below to re-enable it when you're ready.";
      } else {
        mediaKeysLabel.stringValue = @"Hermes still needs Input Monitoring permission for media keys. Open System Settings → Privacy & Security → Input Monitoring and enable Hermes.";
      }
    } else {
      mediaKeysLabel.stringValue = @"";
    }
  }

  if (@available(macOS 10.15, *)) {
    [self installInputMonitoringReminderButtonIfNeeded];
    [self updateInputMonitoringReminderButtonState];
  }

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:name forKey:LAST_PREF_PANE];
}

- (IBAction) showGeneral: (id) sender {
  [self setPreferenceView:general as:@"general"];
}

- (IBAction) showPlayback: (id) sender {
  [self setPreferenceView:playback as:@"playback"];
}

- (IBAction) showNetwork: (id) sender {
  [self setPreferenceView:network as:@"network"];
}

- (IBAction) statusItemIconChanged:(id)sender {
  if (sender == statusItemShowColorIcon) {
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_BW, NO);
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_ALBUM, NO);
  } else if (sender == statusItemShowBlackAndWhiteIcon) {
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_BW, YES);
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_ALBUM, NO);
  } else if (sender == statusItemShowAlbumArt) {
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_BW, NO);
    PREF_KEY_SET_BOOL(STATUS_BAR_ICON_ALBUM, YES);
  }
  [HMSAppDelegate updateStatusItem:sender];
}

- (IBAction) bindMediaChanged: (id) sender {
  SPMediaKeyTap *mediaKeyTap = [HMSAppDelegate playback].mediaKeyTap;
  if (!mediaKeyTap)
    return;

  if (PREF_KEY_BOOL(PLEASE_BIND_MEDIA)) {
    [mediaKeyTap startWatchingMediaKeys];
    if (@available(macOS 10.15, *)) {
      PlaybackController *playback = [HMSAppDelegate playback];
      if (playback.mediaKeyTap != nil && ![playback hasInputMonitoringAccess]) {
        [playback presentInputMonitoringInstructionsAllowingRepeat];
      }
    }
  } else {
    [mediaKeyTap stopWatchingMediaKeys];
  }

  PREF_KEY_SET_BOOL(INPUT_MONITORING_REMINDER_ENABLED, PREF_KEY_BOOL(PLEASE_BIND_MEDIA));

  [HMSAppDelegate refreshInputMonitoringReminder];
  if (@available(macOS 10.15, *)) {
    if (![[HMSAppDelegate playback] hasInputMonitoringAccess]) {
      mediaKeysLabel.stringValue = PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED)
        ? @"Hermes still needs Input Monitoring permission for media keys. Open System Settings → Privacy & Security → Input Monitoring and enable Hermes."
        : @"Input Monitoring reminder is turned off. Click below to re-enable it when you're ready.";
    } else {
      mediaKeysLabel.stringValue = @"";
    }
  }
  [self updateInputMonitoringReminderButtonState];
}

- (void)installInputMonitoringReminderButtonIfNeeded {
  if (inputMonitoringReminderButton != nil || playback == nil || mediaKeysLabel == nil) {
    return;
  }

  // The playback pane may not be in a window when this fires (e.g., tests showing
  // the Network tab first). Defer installation until the label actually has a
  // superview so the constraints share a common ancestor.
  if (mediaKeysLabel.superview == nil) {
    dispatch_async(dispatch_get_main_queue(), ^{
      // Guard again in case the button was created while we were waiting.
      if (self->inputMonitoringReminderButton == nil) {
        [self installInputMonitoringReminderButtonIfNeeded];
      }
    });
    return;
  }

  inputMonitoringReminderButton = [NSButton buttonWithTitle:@"Enable Input Monitoring Reminder…"
                                                     target:self
                                                     action:@selector(enableInputMonitoringReminder:)];
  if (@available(macOS 11.0, *)) {
    inputMonitoringReminderButton.bezelStyle = NSBezelStyleInline;
  } else {
    inputMonitoringReminderButton.bordered = NO;
  }
  inputMonitoringReminderButton.translatesAutoresizingMaskIntoConstraints = NO;
  NSView *targetSuperview = mediaKeysLabel.superview;
  [targetSuperview addSubview:inputMonitoringReminderButton];

  [NSLayoutConstraint activateConstraints:@[
    [inputMonitoringReminderButton.topAnchor constraintEqualToAnchor:mediaKeysLabel.bottomAnchor constant:8.0],
    [inputMonitoringReminderButton.leadingAnchor constraintEqualToAnchor:mediaKeysLabel.leadingAnchor]
  ]];
  inputMonitoringReminderButton.hidden = PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED);
}

- (void)updateInputMonitoringReminderButtonState {
  if (inputMonitoringReminderButton == nil) {
    return;
  }
  BOOL reminderEnabled = PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED);
  inputMonitoringReminderButton.hidden = reminderEnabled;
}

- (IBAction)enableInputMonitoringReminder:(id)sender {
  PREF_KEY_SET_BOOL(INPUT_MONITORING_REMINDER_ENABLED, YES);
  [HMSAppDelegate refreshInputMonitoringReminder];
  [[HMSAppDelegate playback] presentInputMonitoringInstructionsAllowingRepeat];
  if (@available(macOS 10.15, *)) {
    BOOL reminderEnabled = PREF_KEY_BOOL(INPUT_MONITORING_REMINDER_ENABLED);
    if (![[HMSAppDelegate playback] hasInputMonitoringAccess]) {
      mediaKeysLabel.stringValue = reminderEnabled
        ? @"Hermes still needs Input Monitoring permission for media keys. Open System Settings → Privacy & Security → Input Monitoring and enable Hermes."
        : @"Input Monitoring reminder is turned off. Click below to re-enable it when you're ready.";
    } else {
      mediaKeysLabel.stringValue = @"";
    }
  }
  [self updateInputMonitoringReminderButtonState];
}

- (IBAction) show: (id) sender {
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:sender];
}

- (IBAction)proxySettingsChanged:(id)sender {
  BOOL proxyValid = NO;
  NSString *proxyHost;
  NSInteger proxyPort;
  NSInteger enabledProxy = PREF_KEY_INT(ENABLED_PROXY);

  switch (enabledProxy) {
    case PROXY_SYSTEM:
      proxyValid = YES;
      break;
    case PROXY_HTTP:
      proxyHost = PREF_KEY_VALUE(PROXY_HTTP_HOST);
      proxyPort = PREF_KEY_INT(PROXY_HTTP_PORT);
      break;
    case PROXY_SOCKS:
      proxyHost = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
      proxyPort = PREF_KEY_INT(PROXY_SOCKS_PORT);
  }
  if (!proxyValid) {
    proxyServerErrorMessage.hidden = YES;
    [URLConnection validateProxyHostAsync:proxyHost port:proxyPort];
  } else {
    proxyServerErrorMessage.hidden = YES;
  }

  if (enabledProxy == PROXY_SYSTEM && lastEnabledProxy != PROXY_SYSTEM) {
    [URLConnection resetCachedProxySessions];
  }
  lastEnabledProxy = enabledProxy;
}

- (void)proxyServerValidityChanged:(NSNotification *)notification {
  BOOL proxyServerValid = [notification.userInfo[@"isValid"] boolValue];
  proxyServerErrorMessage.hidden = proxyServerValid;
  if (!proxyServerValid) {
    [self showNetwork:nil];
    [window orderFront:nil];
  }
}

@end
