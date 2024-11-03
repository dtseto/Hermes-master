#import "LabelHoverShowFieldCell.h"
#import "LabelHoverShowField.h"

@implementation LabelHoverShowFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect {
<<<<<<< Updated upstream
    NSRect drawingRect = [super drawingRectForBounds:theRect];
    
    NSView *hoverView = ((LabelHoverShowField *)self.controlView).hoverView;
    if (hoverView != nil) {
        CGFloat hoverViewWidth = hoverView.frame.size.width;
        drawingRect.origin.x += hoverViewWidth;
        drawingRect.size.width -= 2 * hoverViewWidth;
    }
    
    return drawingRect;
=======
<<<<<<< Updated upstream
  NSRect drawingRect = [super drawingRectForBounds:theRect];

  NSView *hoverView = ((LabelHoverShowField *)self.controlView).hoverView;
  if (hoverView != nil) {
    CGFloat hoverViewWidth = hoverView.frame.size.width;
    drawingRect.origin.x += hoverViewWidth;
    drawingRect.size.width -= 2 * hoverViewWidth;
  }

  return drawingRect;
>>>>>>> Stashed changes
}

- (void)editWithFrame:(NSRect)aRect
               inView:(NSView *)controlView
               editor:(NSText *)textObj
             delegate:(nullable id)anObject
               event:(NSEvent *)theEvent {
    [self.controlView setNeedsDisplay:YES];
    aRect = NSInsetRect([self drawingRectForBounds:controlView.bounds], 3, 0);
    
    // Use NSAnimationContext to batch the updates
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        // Disable animations to prevent flashing
        [context setDuration:0.0];
        
        [super editWithFrame:aRect
                     inView:controlView
                    editor:textObj
                  delegate:anObject
                    event:theEvent];
        [textObj setFrameSize:aRect.size];
    }];
}

<<<<<<< Updated upstream
=======
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(nullable id)anObject start:(NSInteger)selStart length:(NSInteger)selLength {
  aRect = NSInsetRect([self drawingRectForBounds:controlView.bounds], 3, 0);
  // despite passing smaller rect to super, it ends up too wide the first time unless we set it explicitly
  NSDisableScreenUpdates(); // to prevent flashing of wider rect
  [super selectWithFrame:aRect inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
  [textObj setFrameSize:aRect.size];
  NSEnableScreenUpdates();
=======
    NSRect drawingRect = [super drawingRectForBounds:theRect];
    
    // Get hover view more safely
    LabelHoverShowField *field = (LabelHoverShowField *)self.controlView;
    if (![field isKindOfClass:[LabelHoverShowField class]]) {
        return drawingRect;
    }
    
    NSView *hoverView = field.hoverView;
    if (hoverView != nil) {
        CGFloat hoverViewWidth = NSWidth(hoverView.frame);
        // Ensure we don't create invalid rects
        if (hoverViewWidth > 0 && NSWidth(drawingRect) > (2 * hoverViewWidth)) {
            drawingRect.origin.x += hoverViewWidth;
            drawingRect.size.width -= 2 * hoverViewWidth;
        }
    }
    
    return drawingRect;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    // Ensure proper drawing state
    [NSGraphicsContext saveGraphicsState];
    
    // Calculate the drawing rect
    NSRect drawRect = [self drawingRectForBounds:cellFrame];
    
    // Draw the cell content
    [super drawWithFrame:drawRect inView:controlView];
    
    [NSGraphicsContext restoreGraphicsState];
}

- (void)editWithFrame:(NSRect)aRect
               inView:(NSView *)controlView
               editor:(NSText *)textObj
             delegate:(nullable id)anObject
                event:(NSEvent *)theEvent {
    // Calculate proper edit frame
    NSRect editRect = NSInsetRect([self drawingRectForBounds:controlView.bounds], 3, 0);
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.0];
    
    [super editWithFrame:editRect
                 inView:controlView
                editor:textObj
              delegate:anObject
                event:theEvent];
    
    // Ensure text object has correct frame
    [textObj setFrame:editRect];
    
    [NSAnimationContext endGrouping];
    
    // Mark for display after edit begins
    [controlView setNeedsDisplay:YES];
}

>>>>>>> Stashed changes
- (void)selectWithFrame:(NSRect)aRect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObj
               delegate:(nullable id)anObject
                 start:(NSInteger)selStart
                length:(NSInteger)selLength {
<<<<<<< Updated upstream
    aRect = NSInsetRect([self drawingRectForBounds:controlView.bounds], 3, 0);
    
    // Use NSAnimationContext to batch the updates
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        // Disable animations to prevent flashing
        [context setDuration:0.0];
        
        [super selectWithFrame:aRect
                       inView:controlView
                      editor:textObj
                    delegate:anObject
                       start:selStart
                      length:selLength];
        [textObj setFrameSize:aRect.size];
    }];
=======
    // Calculate proper selection frame
    NSRect selectRect = NSInsetRect([self drawingRectForBounds:controlView.bounds], 3, 0);
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.0];
    
    [super selectWithFrame:selectRect
                   inView:controlView
                  editor:textObj
                delegate:anObject
                   start:selStart
                  length:selLength];
    
    // Ensure text object has correct frame
    [textObj setFrame:selectRect];
    
    [NSAnimationContext endGrouping];
>>>>>>> Stashed changes
>>>>>>> Stashed changes
}

@end
