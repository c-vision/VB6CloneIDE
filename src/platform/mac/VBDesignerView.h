#ifndef VB_DESIGNER_VIEW_H
#define VB_DESIGNER_VIEW_H

#import <Cocoa/Cocoa.h>
#include "core/vb_model.h"

@class VBDesignerView;

@protocol VBDesignerViewDelegate <NSObject>
- (void)designerSelectionChanged:(VBDesignerView *)designer;
- (void)designerDidModifyForm:(VBDesignerView *)designer;
- (void)designerDidFinishCreate:(VBDesignerView *)designer;
- (void)designer:(VBDesignerView *)designer requestCodeForControl:(VbControl *)control;
@end

typedef NS_ENUM(NSInteger, VBDesignerAlign) {
    VBDesignerAlignLeft = 0,
    VBDesignerAlignCenter,
    VBDesignerAlignRight,
    VBDesignerAlignTop,
    VBDesignerAlignMiddle,
    VBDesignerAlignBottom
};

typedef NS_ENUM(NSInteger, VBDesignerSize) {
    VBDesignerSizeWidth = 0,
    VBDesignerSizeHeight,
    VBDesignerSizeBoth
};

typedef NS_ENUM(NSInteger, VBDesignerSpacing) {
    VBDesignerSpacingMakeEqual = 0,
    VBDesignerSpacingIncrease,
    VBDesignerSpacingDecrease,
    VBDesignerSpacingRemove
};

@interface VBDesignerView : NSView
@property (nonatomic) VbForm *form;
@property (nonatomic) VbControl *selected;
@property (nonatomic, copy) NSString *pendingTool;
@property (nonatomic, weak) id<VBDesignerViewDelegate> delegate;
@property (nonatomic, readonly) NSUInteger selectionCount;
- (void)refresh;
- (void)selectControl:(VbControl *)control;
- (void)deleteSelected;
- (NSRect)rectForControl:(VbControl *)control;

/* Format menu operations. All work on the current multi-selection and require it to
   share a single parent; they return NO when there is nothing valid to do. */
- (BOOL)canAlignSelection;
- (BOOL)canSpaceSelection;
- (BOOL)alignSelection:(VBDesignerAlign)mode;
- (BOOL)makeSameSize:(VBDesignerSize)mode;
- (BOOL)spaceSelection:(VBDesignerSpacing)mode horizontal:(BOOL)horizontal;
- (BOOL)centerSelectionInForm;

/* Z-order. The active selection moves as a block, keeping its relative order. */
- (BOOL)canReorderSelection;
- (BOOL)bringSelectionToFront;
- (BOOL)sendSelectionToBack;
@end

#endif
