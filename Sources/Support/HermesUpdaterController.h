#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A tiny helper that prepares the Sparkle updater if the framework is present.
 Updates remain disabled by default so the functionality can be toggled on
 later without shipping the updater today.
 */
@interface HermesUpdaterController : NSObject

+ (instancetype)sharedController;

/// Reflects the persisted preference. Defaults to NO so Sparkle stays dormant.
@property (nonatomic, assign, getter=isUpdatesEnabled) BOOL updatesEnabled;

/// Reads NSUserDefaults and applies the stored preference to the Sparkle updater.
- (void)configureFromDefaults;

/// Persists a new preference value and immediately applies it when Sparkle exists.
- (void)persistUpdatesEnabled:(BOOL)enabled;

/// Invoked by UI elements (e.g. menu item) to trigger a manual check.
- (IBAction)checkForUpdates:(id)sender;

@end

NS_ASSUME_NONNULL_END
