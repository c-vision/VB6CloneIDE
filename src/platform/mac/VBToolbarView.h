#ifndef VB_TOOLBAR_VIEW_H
#define VB_TOOLBAR_VIEW_H

#import <Cocoa/Cocoa.h>

@class VBToolbarView;

@protocol VBToolbarViewDelegate <NSObject>
- (void)toolbarView:(VBToolbarView *)toolbar didSelectIdentifier:(NSString *)identifier;
@end

@interface VBToolbarView : NSView

@property (nonatomic, weak) id<VBToolbarViewDelegate> delegate;

- (void)setButtons:(NSArray<NSDictionary *> *)buttons;
- (void)setEnabled:(BOOL)enabled forIdentifier:(NSString *)identifier;
- (BOOL)isEnabledForIdentifier:(NSString *)identifier;
/* Button hit rect in view coordinates (NSZeroRect when the identifier is unknown). */
- (NSRect)rectForIdentifier:(NSString *)identifier;

@end

#endif
