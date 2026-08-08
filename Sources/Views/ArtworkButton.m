#import "ArtworkButton.h"

@interface ArtworkContainerView ()
- (void)configureFlexibleSizing;
@end

@implementation ArtworkContainerView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    [self configureFlexibleSizing];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self != nil) {
    [self configureFlexibleSizing];
  }
  return self;
}

- (void)configureFlexibleSizing {
  [self setContentHuggingPriority:1.0
                  forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self setContentHuggingPriority:1.0
                  forOrientation:NSLayoutConstraintOrientationVertical];
  [self setContentCompressionResistancePriority:1.0
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self setContentCompressionResistancePriority:1.0
                                 forOrientation:NSLayoutConstraintOrientationVertical];
}

- (NSSize)intrinsicContentSize {
  return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (NSSize)fittingSize {
  return NSZeroSize;
}

- (void)setFrameSize:(NSSize)newSize {
  [super setFrameSize:newSize];
  self.needsLayout = YES;
}

- (void)layout {
  [super layout];

  NSView *artworkView = self.subviews.firstObject;
  if (artworkView == nil) {
    return;
  }

  CGFloat side = MAX(0.0, MIN(NSWidth(self.bounds), NSHeight(self.bounds)));
  artworkView.frame = NSMakeRect((NSWidth(self.bounds) - side) / 2.0,
                                (NSHeight(self.bounds) - side) / 2.0,
                                side,
                                side);
}

@end

@implementation ArtworkButton

- (void)setImage:(NSImage *)image {
  [super setImage:image];
  self.superview.needsLayout = YES;
}

@end
