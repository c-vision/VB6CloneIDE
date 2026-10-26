#ifndef VB_DESIGNER_SELF_TEST_H
#define VB_DESIGNER_SELF_TEST_H

#import <Cocoa/Cocoa.h>

#import "VBDesignerView.h"
#import "VBMenuBarView.h"
#import "VBToolbarView.h"
#include "core/vb_model.h"

/* Drives the real designer view with synthetic mouse events: marquee selection,
   shift-click, group move and group resize. Returns YES when every geometric
   assertion holds. Diagnostics go to stderr. */
BOOL VBRunDesignerSelectionSelfTest(VBDesignerView *designer, VbForm *form);

/* Fires the Format menu items through NSApp sendAction (the same path as a click)
   and asserts the resulting geometry. Expects three controls already selected. */
BOOL VBRunFormatMenuSelfTest(VBMenuBarView *menuBar, VBDesignerView *designer, VbForm *form);

/* Asserts the enabled state of Align / Make Same Size / Spacing / Center in Form. */
BOOL VBCheckFormatMenuState(VBMenuBarView *menuBar, BOOL alignEnabled, BOOL spaceEnabled,
                            BOOL centerEnabled);

/* Asserts the enabled state of the Form Editor toolbar buttons. */
BOOL VBCheckToolbarState(VBToolbarView *toolbar, BOOL alignEnabled, BOOL spaceEnabled);

/* Clicks the Form Editor toolbar buttons with synthetic mouse events and asserts the
   resulting geometry (same actions as the Format menu). Needs three selected controls. */
BOOL VBRunFormatToolbarSelfTest(VBToolbarView *toolbar, VBDesignerView *designer, VbForm *form);

/* Asserts the View > Tab Order... entry is present and usable. */
BOOL VBCheckTabOrderMenu(VBMenuBarView *menuBar);

/* Exercises Format > Order through its menu items (Bring to Front / Send to Back),
   verifies that the new z-order survives a save/reload, and drives the Tab Order
   model (reorder + apply). */
BOOL VBRunZOrderSelfTest(VBMenuBarView *menuBar, VBDesignerView *designer, VbForm *form);

#endif
