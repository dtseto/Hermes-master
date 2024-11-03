#import <SPMediaKeyTap/SPMediaKeyTap.h>

#import "PlaybackController.h"
#import "PreferencesController.h"
#import "URLConnection.h"

@implementation PreferencesController

- (void)awakeFromNib {
  [super awakeFromNib];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(proxyServerValidityChanged:) name:URLConnectionProxyValidityChangedNotification object:nil];
}

- (void)windowDidBecomeMain:(NSNotification *)notification {
  /* See HermesAppDelegate#updateStatusBarIcon */
  [window setCanHide:NO];

  if (PREF_KEY_BOOL(STATUS_BAR_ICON_BW))
    statusItemShowBlackAndWhiteIcon.state = NSOnState;
  else if (PREF_KEY_BOOL(STATUS_BAR_ICON_ALBUM))
    statusItemShowAlbumArt.state = NSOnState;
  else
    statusItemShowColorIcon.state = NSOnState;

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
  } else {
    [mediaKeyTap stopWatchingMediaKeys];
  }
}

- (IBAction) show: (id) sender {
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:sender];
}

- (IBAction)proxySettingsChanged:(id)sender {
    // Validate UI elements first
    if (!proxyServerErrorMessage) {
        NSLog(@"Error: proxyServerErrorMessage outlet not connected");
        return;
    }
    
    BOOL proxyValid = NO;
    NSString *proxyHost = nil;
    NSInteger proxyPort = 0;
    
    // Get proxy type with bounds checking
    NSInteger proxyType = PREF_KEY_INT(ENABLED_PROXY);
    
    // Validate and set proxy configuration based on type
    switch (proxyType) {
        case PROXY_SYSTEM:
            proxyValid = YES;  // System proxy is assumed valid
            break;
            
        case PROXY_HTTP: {
            proxyHost = PREF_KEY_VALUE(PROXY_HTTP_HOST);
            proxyPort = PREF_KEY_INT(PROXY_HTTP_PORT);
            
            // Validate HTTP proxy settings
            if (![self isValidProxyHost:proxyHost port:proxyPort]) {
                NSLog(@"Invalid HTTP proxy configuration - Host: %@, Port: %ld",
                      proxyHost, (long)proxyPort);
            }
            break;
        }
            
        case PROXY_SOCKS: {
            proxyHost = PREF_KEY_VALUE(PROXY_SOCKS_HOST);
            proxyPort = PREF_KEY_INT(PROXY_SOCKS_PORT);
            
            // Validate SOCKS proxy settings
            if (![self isValidProxyHost:proxyHost port:proxyPort]) {
                NSLog(@"Invalid SOCKS proxy configuration - Host: %@, Port: %ld",
                      proxyHost, (long)proxyPort);
            }
            break;
        }
            
        default:
            NSLog(@"Error: Invalid proxy type specified: %ld", (long)proxyType);
            break;
    }
    
    // Only validate non-system proxies
    if (!proxyValid && proxyType != PROXY_SYSTEM) {
        proxyValid = [URLConnection validProxyHost:&proxyHost port:proxyPort];
        
        // Log validation result
        if (!proxyValid) {
            NSLog(@"Proxy validation failed for host: %@, port: %ld",
                  proxyHost, (long)proxyPort);
        }
    }
    
    // Update UI
    proxyServerErrorMessage.hidden = proxyValid;
}

// Helper method for proxy validation
- (BOOL)isValidProxyHost:(NSString *)host port:(NSInteger)port {
    return host.length > 0 && port > 0 && port <= 65535;
}

- (void)proxyServerValidityChanged:(NSNotification *)notification {
    // Validate notification data
    if (!notification.userInfo[@"isValid"]) {
        NSLog(@"Error: Invalid proxy server validation notification data");
        return;
    }
    
    // Get validation status
    BOOL proxyServerValid = [notification.userInfo[@"isValid"] boolValue];
    
    // Update UI
    if (proxyServerErrorMessage) {
        proxyServerErrorMessage.hidden = proxyServerValid;
    } else {
        NSLog(@"Error: proxyServerErrorMessage outlet not connected");
    }
    
    // Show network preferences if proxy is invalid
    if (!proxyServerValid) {
        [self showNetwork:nil];
        
        // Ensure window exists before ordering front
        if (window) {
            [window orderFront:nil];
        } else {
            NSLog(@"Error: window outlet not connected");
        }
    }
}

@end
