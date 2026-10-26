#ifndef VB_TOOLBOX_VIEW_H
#define VB_TOOLBOX_VIEW_H

#import <Cocoa/Cocoa.h>

@class VBToolboxView;

@protocol VBToolboxViewDelegate <NSObject>
- (void)toolboxView:(VBToolboxView *)view didSelectType:(NSString *)type;
@end

@interface VBToolboxView : NSView

@property (nonatomic, weak) id<VBToolboxViewDelegate> delegate;
@property (nonatomic, copy) NSString *selectedType;

- (void)clearSelection;
- (CGFloat)preferredHeight;

@end

#endif
