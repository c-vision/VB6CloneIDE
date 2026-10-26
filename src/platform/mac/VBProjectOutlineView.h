#ifndef VB_PROJECT_OUTLINE_VIEW_H
#define VB_PROJECT_OUTLINE_VIEW_H

#import <Cocoa/Cocoa.h>

#include "core/vb_model.h"

@class VBProjectOutlineView;

@protocol VBProjectOutlineViewDelegate <NSObject>
- (void)projectOutline:(VBProjectOutlineView *)outline didSelectItem:(VbItem *)item;
- (void)projectOutline:(VBProjectOutlineView *)outline didActivateItem:(VbItem *)item;
@end

@interface VBProjectOutlineView : NSView <NSOutlineViewDataSource, NSOutlineViewDelegate>

@property (nonatomic, weak) id<VBProjectOutlineViewDelegate> delegate;

- (void)setProject:(VbProject *)project;
- (void)selectItem:(VbItem *)item;

@end

#endif
