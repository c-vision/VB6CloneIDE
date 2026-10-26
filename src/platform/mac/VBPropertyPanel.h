#ifndef VB_PROPERTY_PANEL_H
#define VB_PROPERTY_PANEL_H

#import <Cocoa/Cocoa.h>

#include "core/vb_model.h"

@class VBPropertyPanel;

@protocol VBPropertyPanelDelegate <NSObject>
- (BOOL)propertyPanel:(VBPropertyPanel *)panel setValue:(NSString *)value forKey:(NSString *)key;
@optional
- (void)propertyPanel:(VBPropertyPanel *)panel didSelectControl:(VbControl *)control;
@end

@interface VBPropertyPanel : NSView <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

@property (nonatomic, weak) id<VBPropertyPanelDelegate> delegate;

- (void)setControl:(VbControl *)control;
- (void)setObjects:(NSArray<NSDictionary *> *)objects;
- (void)reload;
- (VbControl *)control;

@end

#endif
