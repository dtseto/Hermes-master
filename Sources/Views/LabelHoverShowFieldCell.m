#import "LabelHoverShowFieldCell.h"
#import "LabelHoverShowField.h"

@implementation LabelHoverShowFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect {
    NSRect drawingRect = [super drawingRectForBounds:theRect];
    
    NSView *hoverView = ((LabelHoverShowField *)self.controlView).hoverView;
    if (hoverView != nil) {
        CGFloat hoverViewWidth = hoverView.frame.size.width;
        drawingRect.origin.x += hoverViewWidth;
        drawingRect.size.width -= 2 * hoverViewWidth;
    }
    
    return drawingRect;
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

- (void)selectWithFrame:(NSRect)aRect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObj
               delegate:(nullable id)anObject
                 start:(NSInteger)selStart
                length:(NSInteger)selLength {
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
}

@end
