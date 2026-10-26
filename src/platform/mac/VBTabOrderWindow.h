#ifndef VB_TAB_ORDER_WINDOW_H
#define VB_TAB_ORDER_WINDOW_H

#import <Cocoa/Cocoa.h>

#include "core/vb_model.h"

/* Model behind the VB6 Tab Order dialog: the tabbable children of a container in
   TabIndex order. Reordering and Apply are UI independent so they can be tested. */
@interface VBTabOrderModel : NSObject

- (instancetype)initWithContainer:(VbControl *)container;

@property (nonatomic, readonly) VbControl *container;
@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic) NSInteger selectedIndex;

- (NSString *)titleAtIndex:(NSUInteger)index;
- (VbControl *)controlAtIndex:(NSUInteger)index;
- (BOOL)moveSelectionUp;
- (BOOL)moveSelectionDown;
- (void)apply;

@end

@interface VBTabOrderWindow : NSObject

/* Runs the modal VB6-style Tab Order dialog for a container (form or Frame).
   Returns YES when the user accepted a new order, which is then written to TabIndex. */
+ (BOOL)runForContainer:(VbControl *)container;

@end

#endif
