#ifndef VB_MENU_BAR_VIEW_H
#define VB_MENU_BAR_VIEW_H

#import <Cocoa/Cocoa.h>

@interface VBMenuBarView : NSView

@property (nonatomic, copy) NSArray<NSString *> *titles;
@property (nonatomic, copy) NSArray<NSMenu *> *menus;

- (void)setTitles:(NSArray<NSString *> *)titles menus:(NSArray<NSMenu *> *)menus;

@end

#endif
