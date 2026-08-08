#import "PlaybackSplitView.h"

static const CGFloat PlaybackSplitViewDefaultSidebarWidth = 198.0;

@interface PlaybackSplitView ()
@property (nonatomic, weak) NSView *leadingPane;
@property (nonatomic, weak) NSView *centerPane;
@property (nonatomic, weak) NSView *trailingPane;
@end

@implementation PlaybackSplitView

- (instancetype)initWithFrame:(NSRect)frameRect {
  self = [super initWithFrame:frameRect];
  if (self != nil) {
    [self configureSplitView];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self != nil) {
    [self configureSplitView];
  }
  return self;
}

- (void)configureSplitView {
  self.vertical = YES;
  self.dividerStyle = NSSplitViewDividerStyleThin;
  self.delegate = self;
  self.preferredLeadingPaneWidth = PlaybackSplitViewDefaultSidebarWidth;
  self.preferredTrailingPaneWidth = PlaybackSplitViewDefaultSidebarWidth;
  self.leadingPaneVisible = YES;
  self.trailingPaneVisible = YES;
  [self setContentHuggingPriority:1.0
                  forOrientation:NSLayoutConstraintOrientationHorizontal];
  [self setContentCompressionResistancePriority:1.0
                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
}

- (NSSize)intrinsicContentSize {
  return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
}

- (NSSize)fittingSize {
  return NSZeroSize;
}

- (void)setLeadingPane:(NSView *)leadingPane
            centerPane:(NSView *)centerPane
          trailingPane:(NSView *)trailingPane {
  for (NSView *pane in [self.arrangedSubviews copy]) {
    [self removeArrangedSubview:pane];
    [pane removeFromSuperview];
  }

  self.leadingPane = leadingPane;
  self.centerPane = centerPane;
  self.trailingPane = trailingPane;

  for (NSView *pane in @[leadingPane, centerPane, trailingPane]) {
    pane.translatesAutoresizingMaskIntoConstraints = YES;
    pane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self addArrangedSubview:pane];
  }

  leadingPane.hidden = !self.leadingPaneVisible;
  trailingPane.hidden = !self.trailingPaneVisible;

  // The center pane consumes window resizing before either optional sidebar.
  [self setHoldingPriority:300.0 forSubviewAtIndex:0];
  [self setHoldingPriority:200.0 forSubviewAtIndex:1];
  [self setHoldingPriority:300.0 forSubviewAtIndex:2];
  [self tilePanes];
}

- (void)setPreferredLeadingPaneWidth:(CGFloat)preferredLeadingPaneWidth {
  _preferredLeadingPaneWidth = MAX(0.0, preferredLeadingPaneWidth);
  [self tilePanes];
}

- (void)setPreferredTrailingPaneWidth:(CGFloat)preferredTrailingPaneWidth {
  _preferredTrailingPaneWidth = MAX(0.0, preferredTrailingPaneWidth);
  [self tilePanes];
}

- (void)setLeadingPaneVisible:(BOOL)leadingPaneVisible {
  _leadingPaneVisible = leadingPaneVisible;
  self.leadingPane.hidden = !leadingPaneVisible;
  [self tilePanes];
}

- (void)setTrailingPaneVisible:(BOOL)trailingPaneVisible {
  _trailingPaneVisible = trailingPaneVisible;
  self.trailingPane.hidden = !trailingPaneVisible;
  [self tilePanes];
}

- (void)tilePanes {
  if (self.leadingPane == nil || self.centerPane == nil || self.trailingPane == nil) {
    return;
  }

  CGFloat width = MAX(0.0, NSWidth(self.bounds));
  CGFloat height = MAX(0.0, NSHeight(self.bounds));
  NSInteger visiblePaneCount = 1 + self.leadingPaneVisible + self.trailingPaneVisible;
  NSInteger dividerCount = MAX(0, visiblePaneCount - 1);
  CGFloat dividerWidth = dividerCount == 0
    ? 0.0
    : MIN(self.dividerThickness, width / dividerCount);
  CGFloat availableWidth = MAX(0.0, width - (dividerWidth * dividerCount));

  CGFloat leadingWidth = self.leadingPaneVisible ? self.preferredLeadingPaneWidth : 0.0;
  CGFloat trailingWidth = self.trailingPaneVisible ? self.preferredTrailingPaneWidth : 0.0;
  CGFloat preferredSidebarWidth = leadingWidth + trailingWidth;
  CGFloat centerWidth = 0.0;

  if (preferredSidebarWidth <= availableWidth) {
    centerWidth = availableWidth - preferredSidebarWidth;
  } else if (preferredSidebarWidth > 0.0) {
    CGFloat scale = availableWidth / preferredSidebarWidth;
    leadingWidth *= scale;
    trailingWidth *= scale;
  }

  CGFloat x = 0.0;
  if (self.leadingPaneVisible) {
    self.leadingPane.frame = NSMakeRect(x, 0.0, leadingWidth, height);
    x += leadingWidth + dividerWidth;
  } else {
    self.leadingPane.frame = NSMakeRect(0.0, 0.0, 0.0, height);
  }

  self.centerPane.frame = NSMakeRect(x, 0.0, centerWidth, height);
  x += centerWidth;
  if (self.trailingPaneVisible) {
    x += dividerWidth;
    self.trailingPane.frame = NSMakeRect(x, 0.0, trailingWidth, height);
  } else {
    self.trailingPane.frame = NSMakeRect(width, 0.0, 0.0, height);
  }
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
  [self tilePanes];
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
  // Visibility is changed through the sidebar controls so controller state,
  // preferences, and titlebar tooltips remain synchronized.
  return NO;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMinCoordinate:(CGFloat)proposedMinimumPosition
               ofSubviewAt:(NSInteger)dividerIndex {
  return proposedMinimumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainMaxCoordinate:(CGFloat)proposedMaximumPosition
               ofSubviewAt:(NSInteger)dividerIndex {
  return proposedMaximumPosition;
}

- (CGFloat)splitView:(NSSplitView *)splitView
    constrainSplitPosition:(CGFloat)proposedPosition
               ofSubviewAt:(NSInteger)dividerIndex {
  if (dividerIndex == 0 && self.leadingPaneVisible) {
    _preferredLeadingPaneWidth = MAX(0.0, proposedPosition);
  } else if (dividerIndex == 1 && self.trailingPaneVisible) {
    _preferredTrailingPaneWidth = MAX(0.0,
      NSWidth(self.bounds) - proposedPosition - self.dividerThickness);
  }
  return proposedPosition;
}

- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex {
  if (dividerIndex == 0) {
    return !self.leadingPaneVisible;
  }
  if (dividerIndex == 1) {
    return !self.trailingPaneVisible;
  }
  return NO;
}

@end
