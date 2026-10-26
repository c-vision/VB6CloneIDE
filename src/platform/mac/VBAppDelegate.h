#ifndef VB_APP_DELEGATE_H
#define VB_APP_DELEGATE_H

#import <Cocoa/Cocoa.h>

@class VBEditorWindowController;

@interface VBAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, copy) NSString *startupPath;
@property (nonatomic, strong, readonly) VBEditorWindowController *editor;

- (IBAction)newProject:(id)sender;
- (IBAction)openProject:(id)sender;
- (IBAction)openSampleProject:(id)sender;
- (IBAction)saveProject:(id)sender;
- (IBAction)saveProjectAs:(id)sender;
- (IBAction)addForm:(id)sender;
- (IBAction)runProject:(id)sender;
- (IBAction)stopProject:(id)sender;
- (IBAction)showDesigner:(id)sender;
- (IBAction)showCode:(id)sender;
- (IBAction)showAbout:(id)sender;

@end

#endif
