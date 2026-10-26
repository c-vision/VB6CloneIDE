CC ?= cc
# -MMD -MP: the structs in core/*.h are shared with the Objective-C shell, so a header
# change must rebuild every object instead of mixing layouts (silent memory corruption).
CFLAGS = -std=c99 -O2 -Wall -Wextra -Isrc -D_POSIX_C_SOURCE=200809L -MMD -MP
OBJCFLAGS = -std=gnu11 -O2 -Wall -Wextra -Isrc -fobjc-arc -mmacosx-version-min=11.0 -MMD -MP
LDLIBS = -framework Cocoa -framework UniformTypeIdentifiers

CORE = src/core/vb_util.c src/core/vb_model.c src/core/vb_parse.c src/core/vb_code.c \
       src/core/vb_grid.c
TOOL = src/tools/vbtool.c
MAC = src/platform/mac/main.m \
      src/platform/mac/VBAppDelegate.m \
      src/platform/mac/VBEditorWindow.m \
      src/platform/mac/VBMenuBarView.m \
      src/platform/mac/VBToolbarView.m \
      src/platform/mac/VBToolboxView.m \
      src/platform/mac/VBProjectOutlineView.m \
      src/platform/mac/VBPropertyPanel.m \
      src/platform/mac/VBCodeEditor.m \
      src/platform/mac/VBRuntimeWindow.m \
      src/platform/mac/VBDesignerView.m \
      src/platform/mac/VBTabOrderWindow.m \
      src/platform/mac/VBDesignerSelfTest.m \
      src/platform/mac/VBTheme.m

CORE_OBJ = $(CORE:%.c=build/obj/%.o)
TOOL_OBJ = $(TOOL:%.c=build/obj/%.o)
MAC_OBJ = $(MAC:%.m=build/obj/%.o)
DEPS = $(CORE_OBJ:.o=.d) $(TOOL_OBJ:.o=.d) $(MAC_OBJ:.o=.d)
APP = build/VB6CloneIDE.app
APP_BIN = $(APP)/Contents/MacOS/VB6CloneIDE

all: build/vbtool app

build:
	@mkdir -p build

build/obj/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

build/obj/%.o: %.m
	@mkdir -p $(dir $@)
	$(CC) $(OBJCFLAGS) -c $< -o $@

build/vbtool: $(CORE_OBJ) $(TOOL_OBJ) | build
	$(CC) $(CORE_OBJ) $(TOOL_OBJ) -o $@

$(APP_BIN): $(CORE_OBJ) $(MAC_OBJ) src/platform/mac/Info.plist resources/AppIcon.icns
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources/Samples/HelloWorld
	$(CC) $(CORE_OBJ) $(MAC_OBJ) $(LDLIBS) -o $@
	cp src/platform/mac/Info.plist $(APP)/Contents/Info.plist
	cp resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp samples/HelloWorld/HelloWorld.vbp samples/HelloWorld/frmHello.frm $(APP)/Contents/Resources/Samples/HelloWorld/
	-codesign --force --sign - $(APP) >/dev/null 2>&1

app: $(APP_BIN)

# Headless: the harness links only the C core, so no IDE window is ever opened (it does
# not even build the app bundle).
check: build/vbtool
	./build/vbtool check

clean:
	rm -rf build

-include $(DEPS)

.PHONY: all app check clean
