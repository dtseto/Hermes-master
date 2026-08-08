#import <Cocoa/Cocoa.h>

@interface PlaybackSplitView : NSSplitView <NSSplitViewDelegate>

@property (nonatomic) CGFloat preferredLeadingPaneWidth;
@property (nonatomic) CGFloat preferredTrailingPaneWidth;
@property (nonatomic, getter=isLeadingPaneVisible) BOOL leadingPaneVisible;
@property (nonatomic, getter=isTrailingPaneVisible) BOOL trailingPaneVisible;

- (void)setLeadingPane:(NSView *)leadingPane
            centerPane:(NSView *)centerPane
          trailingPane:(NSView *)trailingPane;

@end
