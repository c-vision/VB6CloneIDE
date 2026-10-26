#ifndef VB_THEME_H
#define VB_THEME_H

#import <Cocoa/Cocoa.h>

#define VB_SCALE (1.5 / 15.0)
#define VB_TITLE_HEIGHT 21.0
#define VB_MENU_HEIGHT 22.0

/* Classic Windows 95 / Visual Basic 6 system colors */
NSColor *VBColorFace(void);
NSColor *VBColorLight(void);
NSColor *VBColorShadow(void);
NSColor *VBColorDarkShadow(void);
NSColor *VBColorWindow(void);
NSColor *VBColorText(void);
NSColor *VBColorTitleBar(void);
NSColor *VBColorTitleInactive(void);
NSColor *VBColorTitleText(void);
NSColor *VBColorSelection(void);
NSColor *VBColorGrid(void);
NSColor *VBColorCodeBackground(void);
NSColor *VBColorCodeText(void);
NSColor *VBColorKeyword(void);
NSColor *VBColorComment(void);
NSColor *VBColorString(void);
NSColor *VBColorNumber(void);
NSColor *VBColorBuiltin(void);
NSColor *VBColorConstant(void);
NSColor *VBColorType(void);
NSColor *VBColorGutter(void);
NSColor *VBColorGutterText(void);

NSColor *VBColorChromeTop(void);
NSColor *VBColorChromeBottom(void);
NSColor *VBColorPanel(void);
NSColor *VBColorPanelAlt(void);
NSColor *VBColorPanelBorder(void);
NSColor *VBColorMutedText(void);
NSColor *VBColorAccent(void);
NSColor *VBColorAccentSoft(void);
NSColor *VBColorHover(void);
NSColor *VBColorRunning(void);
NSColor *VBColorCurrentLine(void);
/* Break mode: the statement the interpreter is paused on (VB6 yellow bar). */
NSColor *VBColorBreakLine(void);
/* Breakpoint dot in the code margin (VB6 dark red). */
NSColor *VBColorBreakpoint(void);

NSGradient *VBChromeGradient(void);
NSGradient *VBPanelHeaderGradient(void);

NSFont *VBFontUI(void);
NSFont *VBFontUIBold(void);
NSFont *VBFontUISmall(void);
NSFont *VBFontUIMedium(void);
NSFont *VBFontCode(void);
NSFont *VBFontCodeBold(void);

double VBTwipsToPoints(int twips);
int VBPointsToTwips(double points);

/* Classic 3D chrome drawing. All helpers fill the face color first. */
void VBFillFace(NSRect rect);
void VBDrawRaisedBevel(NSRect rect);
void VBDrawPressedBevel(NSRect rect);
void VBDrawSunkenBevel(NSRect rect);
void VBDrawEtchedBorder(NSRect rect);
void VBDrawPanelBorder(NSRect rect);
void VBDrawTitleBar(NSRect rect, NSString *title, BOOL active,
                    BOOL closeBox, BOOL minimizeBox, BOOL maximizeBox);
void VBDrawClassicButton(NSRect rect, BOOL pressed);
void VBDrawClassicCheck(NSRect box, int state);
void VBDrawClassicRadio(NSRect box, int state);
void VBDrawClassicArrow(NSRect rect, BOOL down, NSColor *color);
void VBDrawToolbarButton(NSRect rect, BOOL pressed, BOOL hovered);
void VBDrawClassicIcon(NSRect rect, NSString *kind);
/* Data control: caption plus the VB6 |< < > >| navigation strip. */
void VBDrawClassicDataControl(NSRect rect, NSString *caption);
/* DataGrid/FlexGrid: sunken window, optional column header and cell grid. */
void VBDrawClassicDataGrid(NSRect rect, int headers, int columnWidth, int rowHeight);
void VBDrawStatusPanel(NSRect rect);

#endif
