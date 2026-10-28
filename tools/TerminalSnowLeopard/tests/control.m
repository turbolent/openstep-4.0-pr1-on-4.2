/* Development-only AppKit event tests. Excluded from release builds. */
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <sys/time.h>
#include <unistd.h>
#import <objc/objc-class.h>
static NSString *snowTestDirectory;
static id snowRenderingTestProfile;
static NSButton *snowFindButton(NSView *view, NSString *title) {
    NSArray *children;
    unsigned i;
    if ([view isKindOfClass:[NSButton class]] && [[(NSButton *)view title] isEqual:title])
        return (NSButton *)view;
    children = [view subviews];
    for (i = 0; i < [children count]; i++) {
        NSButton *found = snowFindButton([children objectAtIndex:i], title);
        if (found)
            return found;
    }
    return nil;
}
static void snowWakeModal(NSWindow *window) {
    /* Native modal loops finish after receiving the button-release event.
     * performClick: invokes the action without supplying that event. */
    NSEvent *release = [NSEvent keyEventWithType:NSKeyUp
                                        location:NSZeroPoint
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:[window windowNumber]
                                         context:[NSDPSContext currentContext]
                                      characters:@""
                     charactersIgnoringModifiers:@""
                                       isARepeat:NO
                                         keyCode:0];
    [NSApp postEvent:release atStart:NO];
}
static id snowMenuItem(NSMenu *menu, NSString *title, unsigned depth) {
    unsigned i;
    if (depth > 8)
        return nil;
    for (i = 0; i < [menu numberOfItems]; i++) {
        id item = [menu itemAtIndex:i], submenu = [item submenu], found;
        if ([[item title] isEqual:title] && !submenu)
            return item;
        if ([submenu isKindOfClass:[NSMenu class]] &&
            (found = snowMenuItem(submenu, title, depth + 1)))
            return found;
    }
    return nil;
}
static void snowDescribeMenu(NSMenu *menu, NSMutableString *report, unsigned depth) {
    unsigned i;
    if (depth > 8)
        return;
    for (i = 0; i < [menu numberOfItems]; i++) {
        id item = [menu itemAtIndex:i], submenu = [item submenu];
        [report appendFormat:@"%u %@ action=%@ tag=%d key=%@ target=%@\n", depth, [item title],
                             ([item action] ? NSStringFromSelector([item action]) : @"-"),
                             [item tag], [item keyEquivalent], [[item target] class]];
        if ([submenu isKindOfClass:[NSMenu class]])
            snowDescribeMenu(submenu, report, depth + 1);
    }
}
static NSView *snowFindTerminal(NSView *view) {
    NSArray *children;
    unsigned i;
    if ([view isKindOfClass:NSClassFromString(@"TTView")])
        return view;
    children = [view subviews];
    for (i = 0; i < [children count]; i++) {
        NSView *found = snowFindTerminal([children objectAtIndex:i]);
        if (found)
            return found;
    }
    return nil;
}
static void snowDescribeView(NSView *view, NSMutableString *text, unsigned depth) {
    NSArray *children = [view subviews];
    unsigned i;
    if (depth > 20)
        return;
    [text appendFormat:@"%u %@ frame=%@ bounds=%@\n", depth, [view class],
                       NSStringFromRect([view frame]), NSStringFromRect([view bounds])];
    if ([view isKindOfClass:NSClassFromString(@"TTView")]) {
        Ivar ivar = class_getInstanceVariable([view class], "_cellSize");
        NSSize size = *(NSSize *)((char *)view + ivar->ivar_offset);
        [text appendFormat:@"cell=%@\n", NSStringFromSize(size)];
    }
    if ([view isKindOfClass:[NSScroller class]])
        [text appendFormat:@"value=%g proportion=%g\n", [(NSScroller *)view floatValue],
                           [(NSScroller *)view knobProportion]];
    for (i = 0; i < [children count]; i++)
        snowDescribeView([children objectAtIndex:i], text, depth + 1);
}
static NSWindow *snowTestWindow(void) {
    NSArray *windows = [NSApp windows];
    NSWindow *key = [NSApp keyWindow];
    unsigned i;
    Class terminal = NSClassFromString(@"TTWindow");
    if ([key isKindOfClass:terminal] && [key isVisible])
        return key;
    key = [NSApp mainWindow];
    if ([key isKindOfClass:terminal] && [key isVisible])
        return key;
    for (i = 0; i < [windows count]; i++) {
        key = [windows objectAtIndex:i];
        if ([key isKindOfClass:terminal] && [key isVisible])
            return key;
    }
    return nil;
}
static NSView *snowBoundControl(NSView *view, NSString *key, NSMutableString *report) {
    NSArray *children = [view subviews];
    unsigned i;
    NSArray *names = [NSArray arrayWithObjects:@"value", @"selectedIndex", @"selectedTag", nil];
    for (i = 0; i < [names count]; i++) {
        NSDictionary *binding = [view infoForBinding:[names objectAtIndex:i]];
        if (binding) {
            NSString *path = [binding objectForKey:@"NSObservedKeyPath"];
            if (report)
                [report
                    appendFormat:@"%@ %@ %@=%@\n", [view class], [names objectAtIndex:i], path,
                                 [[binding objectForKey:@"NSObservedObject"] valueForKeyPath:path]];
            if (key && [key isEqual:path])
                return view;
        }
    }
    for (i = 0; i < [children count]; i++) {
        NSView *found = snowBoundControl([children objectAtIndex:i], key, report);
        if (found)
            return found;
    }
    return nil;
}
@interface SnowTestControl : NSObject
+ (void)poll:(id)sender;
@end
@implementation SnowTestControl
+ (void)poll:(id)sender {
    NSString *request = [snowTestDirectory stringByAppendingPathComponent:@"test.request"];
    NSData *data = [NSData dataWithContentsOfFile:request];
    NSString *message, *identifier, *operation, *payload;
    NSRange split;
    NSMutableString *reply;
    NSWindow *window;
    unsigned i;
    struct timeval started, finished;
    if (!data)
        return;
    [[NSFileManager defaultManager] removeFileAtPath:request handler:nil];
    message = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    split = [message rangeOfString:@"\n"];
    if (split.location == NSNotFound)
        return;
    identifier = [message substringToIndex:split.location];
    message = [message substringFromIndex:split.location + 1];
    split = [message rangeOfString:@"\n"];
    operation = split.location == NSNotFound ? message : [message substringToIndex:split.location];
    payload = split.location == NSNotFound ? @"" : [message substringFromIndex:split.location + 1];
    reply = [NSMutableString stringWithFormat:@"%@ ", identifier];
    gettimeofday(&started, NULL);
    window = snowTestWindow();
    NS_DURING
        if ([operation isEqual:@"menus"]) {
            snowDescribeMenu([NSApp mainMenu], reply, 0);
        } else if ([operation isEqual:@"menu-item"]) {
            id item = snowMenuItem([NSApp mainMenu], payload, 0);
            if (!item)
                [NSException raise:NSInvalidArgumentException format:@"No menu item %@", payload];
            [reply appendFormat:@"sent=%d", [NSApp sendAction:[item action]
                                                           to:[item target]
                                                         from:item]];
        } else if ([operation isEqual:@"import-profile"]) {
            SEL selector = sel_registerName("openFile:");
            BOOL opened = ((BOOL(*)(id, SEL, id))[NSApp methodForSelector:selector])(
                NSApp, selector, payload);
            [reply appendFormat:@"opened=%d", opened];
        } else if ([operation isEqual:@"remove-test-profile"]) {
            id manager = [NSClassFromString(@"TTProfileManager")
                performSelector:@selector(sharedProfileManager)];
            NSArray *profiles = [manager performSelector:@selector(profiles)];
            unsigned index;
            BOOL removed = NO;
            for (index = 0; index < [profiles count]; index++) {
                id profile = [profiles objectAtIndex:index];
                id name = [profile performSelector:@selector(name)];
                if ([name isEqual:@"Port validation 20261028"] ||
                    [name isEqual:@"Import-validation"]) {
                    SEL selector = sel_registerName("removeObjectFromProfilesAtIndex:");
                    ((void (*)(id, SEL, unsigned))[manager methodForSelector:selector])(
                        manager, selector, index);
                    removed = YES;
                    break;
                }
            }
            [reply appendFormat:@"removed=%d", removed];
        } else if ([operation isEqual:@"run-command"]) {
            id controller = [NSClassFromString(@"TTRunCommandPanelController")
                performSelector:@selector(sharedRunCommandPanel)];
            id combo;
            [[controller window] makeFirstResponder:nil];
            combo = [controller valueForKey:@"_commandCombo"];
            [combo setStringValue:payload];
            [reply appendFormat:@"command=%@ ", [combo stringValue]];
            [controller performSelector:@selector(commandEntered:) withObject:combo];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"button"]) {
            NSWindow *panel = [NSApp keyWindow];
            NSButton *button = snowFindButton([panel contentView], payload);
            if (!button)
                [NSException raise:NSInvalidArgumentException format:@"No button %@", payload];
            [button performClick:nil];
            snowWakeModal(panel);
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"dismiss"]) {
            NSWindow *key = [NSApp keyWindow];
            if ([[key title] isEqual:@"New Command"])
                [key orderOut:nil];
            else if ([key isKindOfClass:[NSSavePanel class]])
                [key cancel:nil];
            else if (key != window) {
                NSButton *button = snowFindButton([key contentView], @"Cancel");
                if (!button)
                    button = snowFindButton([key contentView], @"OK");
                if (!button)
                    button = snowFindButton([key contentView], @"Close");
                if (button)
                    [button performClick:nil];
                else
                    [key performClose:nil];
            } else
                [NSException raise:NSInvalidArgumentException
                            format:@"Refusing to dismiss shell window"];
            [reply appendString:@"OK"];
            snowWakeModal(key);
        } else if ([operation isEqual:@"save-panel"]) {
            NSSavePanel *panel = (NSSavePanel *)[NSApp keyWindow];
            id form;
            if (![panel isKindOfClass:[NSSavePanel class]])
                [NSException raise:NSInvalidArgumentException format:@"No save panel is open"];
            [panel setDirectory:[payload stringByDeletingLastPathComponent]];
            form = [panel valueForKey:@"_form"];
            [panel selectText:nil];
            if ([[panel firstResponder] respondsToSelector:@selector(setString:)])
                [(NSText *)[panel firstResponder] setString:[payload lastPathComponent]];
            [panel makeFirstResponder:panel];
            [[form cellAtRow:0 column:0] setStringValue:[payload lastPathComponent]];
            {
                NSButton *button = [panel valueForKey:@"_okButton"];
                if (![button isKindOfClass:[NSButton class]])
                    [NSException raise:NSInvalidArgumentException format:@"No native Save button"];
                [reply appendFormat:@"button=%@ enabled=%d action=%@ form=%@ value=%@ ",
                                    [button class], [button isEnabled],
                                    NSStringFromSelector([button action]), [form class],
                                    [form stringValue]];
                [button performClick:nil];
                snowWakeModal(panel);
                [reply appendFormat:@"filename=%@", [panel filename]];
            }
        } else if ([operation isEqual:@"focus"]) {
            [NSApp deactivate];
            [NSApp activateIgnoringOtherApps:YES];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"drag-select"]) {
            NSView *terminal = snowFindTerminal([window contentView]);
            Ivar ivar = class_getInstanceVariable([terminal class], "_cellSize");
            NSSize cell = *(NSSize *)((char *)terminal + ivar->ivar_offset);
            int row = 1, start = 0, end = 10, step;
            NSPoint point;
            NSEvent *event;
            sscanf([payload cString], "%d %d %d", &row, &start, &end);
            [NSApp activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            /* Queue drag and release before entering the stock tracking loop. */
            for (step = 1; step >= 0; step--) {
                point = NSMakePoint((end + 0.5) * cell.width, (row + 0.5) * cell.height);
                if (![terminal isFlipped])
                    point.y = [terminal bounds].size.height - point.y;
                point = [terminal convertPoint:point toView:nil];
                event = [NSEvent mouseEventWithType:step ? NSLeftMouseUp : NSLeftMouseDragged
                                           location:point
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:[window windowNumber]
                                            context:[NSDPSContext currentContext]
                                        eventNumber:step + 2
                                         clickCount:1
                                           pressure:step ? 0 : 1];
                [NSApp postEvent:event atStart:YES];
            }
            point = NSMakePoint((start + 0.5) * cell.width, (row + 0.5) * cell.height);
            if (![terminal isFlipped])
                point.y = [terminal bounds].size.height - point.y;
            point = [terminal convertPoint:point toView:nil];
            event = [NSEvent mouseEventWithType:NSLeftMouseDown
                                       location:point
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:[window windowNumber]
                                        context:[NSDPSContext currentContext]
                                    eventNumber:1
                                     clickCount:1
                                       pressure:1];
            [NSApp sendEvent:event];
            [reply appendFormat:@"selected=%@", [terminal performSelector:@selector(selectedText)]];
        } else if ([operation isEqual:@"selection-state"]) {
            NSView *terminal = snowFindTerminal([window contentView]);
            id profile = [terminal valueForKey:@"_profile"];
            id color = [profile valueForKey:@"SelectionColor"];
            [reply appendFormat:@"selection=%@ color=%@ rgb=%@ alpha=%g\n",
                                [terminal performSelector:@selector(selectedText)], color,
                                [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace],
                                [color alphaComponent]];
            [terminal setNeedsDisplay:YES];
            [window displayIfNeeded];
        } else if ([operation isEqual:@"prefs-tree"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            snowDescribeView([[controller window] contentView], reply, 0);
        } else if ([operation isEqual:@"double-click"]) {
            NSView *terminal = snowFindTerminal([window contentView]);
            Ivar ivar = class_getInstanceVariable([terminal class], "_cellSize");
            NSSize cell = *(NSSize *)((char *)terminal + ivar->ivar_offset);
            int row = 1, column = 4;
            NSPoint point;
            NSEvent *down, *up;
            sscanf([payload cString], "%d %d", &row, &column);
            point = NSMakePoint((column + 0.5) * cell.width, (row + 0.5) * cell.height);
            if (![terminal isFlipped])
                point.y = [terminal bounds].size.height - point.y;
            point = [terminal convertPoint:point toView:nil];
            [window makeKeyAndOrderFront:nil];
            down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                      location:point
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:[window windowNumber]
                                       context:[NSDPSContext currentContext]
                                   eventNumber:1
                                    clickCount:2
                                      pressure:1];
            up = [NSEvent mouseEventWithType:NSLeftMouseUp
                                    location:point
                               modifierFlags:0
                                   timestamp:0
                                windowNumber:[window windowNumber]
                                     context:[NSDPSContext currentContext]
                                 eventNumber:2
                                  clickCount:2
                                    pressure:0];
            [NSApp postEvent:up atStart:YES];
            [NSApp sendEvent:down];
            [reply appendFormat:@"selected=%@", [terminal performSelector:@selector(selectedText)]];
        } else if ([operation isEqual:@"close-prefs"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            [[controller window] performClose:nil];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"dump"]) {
            NSArray *windows = [NSApp windows];
            for (i = 0; i < [windows count]; i++) {
                NSWindow *candidate = [windows objectAtIndex:i];
                [reply appendFormat:@"%@ title=%@ visible=%d frame=%@ responder=%@\n",
                                    [candidate class], [candidate title], [candidate isVisible],
                                    NSStringFromRect([candidate frame]),
                                    [[candidate firstResponder] class]];
                if ([candidate isKindOfClass:NSClassFromString(@"TTWindow")]) {
                    id controller = [candidate performSelector:@selector(windowController)];
                    id tab = [controller performSelector:@selector(selectedTabController)];
                    id shell = [tab performSelector:@selector(shell)];
                    [reply appendFormat:@"shell=%@ pid=%d\n",
                                        [shell performSelector:@selector(shellCommand)],
                                        (int)[shell performSelector:@selector(pid)]];
                    snowDescribeView([candidate contentView], reply, 0);
                }
            }
        } else if ([operation isEqual:@"preview-cell"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            NSTableView *table = [controller valueForKey:@"profilesTableView"];
            id cell = [[[table tableColumns] objectAtIndex:0] dataCell];
            NSImage *canvas = [[[NSImage alloc] initWithSize:NSMakeSize(160, 44)] autorelease];
            [cell setStringValue:payload];
            [canvas lockFocus];
            [cell drawInteriorWithFrame:NSMakeRect(0, 0, 160, 44) inView:table];
            [canvas unlockFocus];
            [[canvas TIFFRepresentation]
                writeToFile:[snowTestDirectory stringByAppendingPathComponent:@"cell-final.tiff"]
                 atomically:YES];
            [reply appendFormat:@"cell=%@ source=%@ image=%@ title=%@\n", [cell class],
                                [[cell valueForKey:@"_dataSource"] class],
                                [[cell valueForKey:@"_thumbnailCell"] image], [cell stringValue]];
            [table reloadData];
        } else if ([operation isEqual:@"preview"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            id manager = [NSClassFromString(@"TTProfileManager")
                performSelector:@selector(sharedProfileManager)];
            id profile = [manager performSelector:@selector(profileWithName:) withObject:payload];
            SEL selector = sel_getUid("thumbnailOfSize:forProfile:");
            id image = ((id(*)(id, SEL, NSSize, id))[controller methodForSelector:selector])(
                controller, selector, NSMakeSize(40, 25), profile);
            NSData *pixels = [image TIFFRepresentation];
            [pixels writeToFile:[snowTestDirectory
                                    stringByAppendingPathComponent:@"thumbnail-final.tiff"]
                     atomically:YES];
            [reply appendFormat:@"%@ size=%@ bytes=%u", [image class],
                                NSStringFromSize([image size]), [pixels length]];
        } else if ([operation isEqual:@"paste"]) {
            NSPasteboard *board = [NSPasteboard generalPasteboard];
            [board declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
            [board setString:payload forType:NSStringPboardType];
            [window makeKeyAndOrderFront:nil];
            [reply appendFormat:@"sent=%d", [NSApp sendAction:@selector(paste:) to:nil from:nil]];
        } else if ([operation isEqual:@"find"]) {
            id panel =
                [NSClassFromString(@"TTFindPanel") performSelector:@selector(sharedFindPanel)];
            id terminal = snowFindTerminal([window contentView]);
            [window makeKeyAndOrderFront:nil];
            [[panel valueForKey:@"findPatternField"] setStringValue:payload];
            [[panel valueForKey:@"wrapAroundCheckbox"] setState:1];
            [panel performSelector:@selector(findNext:) withObject:nil];
            [reply appendFormat:@"selected=%@", [terminal performSelector:@selector(selectedText)]];
        } else if ([operation isEqual:@"contents"]) {
            id terminal = snowFindTerminal([window contentView]);
            [reply appendString:[terminal performSelector:NSSelectorFromString(@"allText")]];
        } else if ([operation isEqual:@"resize"]) {
            float width = 700, height = 400;
            if ([payload length])
                sscanf([payload cString], "%f %f", &width, &height);
            [window setContentSize:NSMakeSize(width, height)];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"clipboard"]) {
            [reply
                appendString:[[NSPasteboard generalPasteboard] stringForType:NSStringPboardType]];
        } else if ([operation isEqual:@"font-state"]) {
            NSDictionary *defaults =
                [[NSUserDefaults standardUserDefaults] dictionaryRepresentation];
            NSArray *keys = [defaults allKeys];
            if ([payload isEqual:@"refresh"])
                [NSFont performSelector:@selector(initializeUserAndSystemFonts)];
            [reply appendFormat:@"title=%@ menu=%@ system=%@ bold=%@\n",
                                [NSFont titleBarFontOfSize:0], [NSFont menuFontOfSize:0],
                                [NSFont systemFontOfSize:0], [NSFont boldSystemFontOfSize:0]];
            [reply appendFormat:@"explicit-bold=%@\n", [NSFont fontWithName:@"Helvetica-Bold"
                                                                       size:12]];
            [reply appendFormat:@"defaults-bold=%@\n", [[NSUserDefaults standardUserDefaults]
                                                           stringForKey:@"NSBoldSystemFont"]];
            for (i = 0; i < [keys count]; i++) {
                NSString *key = [keys objectAtIndex:i];
                if ([key rangeOfString:@"Font"].location != NSNotFound)
                    [reply appendFormat:@"%@=%@\n", key, [defaults objectForKey:key]];
            }
        } else if ([operation isEqual:@"position"]) {
            [window setFrameOrigin:NSMakePoint(180, 600)];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"prefs-bindings"] || [operation isEqual:@"prefs-toggle"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            NSView *root = [[controller window] contentView];
            if ([operation isEqual:@"prefs-bindings"]) {
                id profiles = [NSClassFromString(@"TTProfileManager")
                    performSelector:@selector(sharedProfileManager)];
                id selection =
                    [[controller valueForKey:@"profilesController"] valueForKey:@"selection"];
                NSArray *all = [profiles valueForKey:@"profiles"];
                [reply appendFormat:@"selection=%x %@ manager-index=%u values=%@\n",
                                    (unsigned)selection, [selection valueForKey:@"name"],
                                    [all indexOfObjectIdenticalTo:selection],
                                    [selection valueForKey:@"scopeValues"]];
                [reply appendFormat:@"manager loading=%@ saved=%@\n",
                                    [profiles valueForKey:@"isLoadingFromDefaults"],
                                    [[[NSUserDefaults standardUserDefaults]
                                        dictionaryForKey:@"Window Settings"]
                                        objectForKey:[selection valueForKey:@"name"]]];
                [reply appendFormat:@"dependencies=%@\n",
                                    [[selection class]
                                        keyPathsForValuesAffectingValueForKey:@"profileKeys"]];
                {
                    id preview = [controller performSelector:@selector(thumbnailView)];
                    [reply appendFormat:@"preview=%@ frame=%@ bounds=%@ visible=%@\n",
                                        [preview class], NSStringFromRect([preview frame]),
                                        NSStringFromRect([preview bounds]),
                                        NSStringFromRect([preview visibleRect])];
                }
                {
                    NSTableView *table = [controller valueForKey:@"profilesTableView"];
                    id cell = [[[table tableColumns] objectAtIndex:0] dataCell];
                    [reply appendFormat:@"cell=%@ source=%@ image=%@ title=%@\n", [cell class],
                                        [[cell valueForKey:@"_dataSource"] class],
                                        [[cell valueForKey:@"_thumbnailCell"] image],
                                        [cell stringValue]];
                }
                snowBoundControl(root, nil, reply);
            } else {
                NSButton *button = (NSButton *)snowBoundControl(root, payload, nil);
                if (![button isKindOfClass:[NSButton class]])
                    [NSException raise:NSInvalidArgumentException
                                format:@"No checkbox for %@", payload];
                [button performClick:nil];
                snowBoundControl(root, nil, reply);
            }
        } else if ([operation isEqual:@"render-setup"]) {
            id manager = [NSClassFromString(@"TTProfileManager")
                performSelector:@selector(sharedProfileManager)];
            id source = [manager performSelector:@selector(profileWithName:) withObject:payload];
            NSString *name = [NSString stringWithFormat:@"Port rendering test %d", getpid()];
            if (snowRenderingTestProfile || !source ||
                [manager performSelector:@selector(profileWithName:) withObject:name])
                [NSException raise:NSInvalidArgumentException
                            format:@"Cannot create rendering test profile"];
            snowRenderingTestProfile = [source copy];
            if (snowRenderingTestProfile == source ||
                [source valueForKey:@"scopeValues"] ==
                    [snowRenderingTestProfile valueForKey:@"scopeValues"])
                [NSException raise:NSInternalInconsistencyException
                            format:@"Test profile is not independent"];
            [snowRenderingTestProfile setValue:name forKey:@"name"];
            [manager performSelector:@selector(setProfile:forName:)
                          withObject:snowRenderingTestProfile
                          withObject:name];
            [reply appendString:name];
        } else if ([operation isEqual:@"render-cleanup"]) {
            id manager = [NSClassFromString(@"TTProfileManager")
                performSelector:@selector(sharedProfileManager)];
            NSArray *windows = [[NSArray alloc] initWithArray:[NSApp windows]];
            NSArray *all;
            NSString *name = [snowRenderingTestProfile valueForKey:@"name"];
            for (i = 0; i < [windows count]; i++) {
                NSWindow *candidate = [windows objectAtIndex:i];
                if ([candidate isKindOfClass:NSClassFromString(@"TTWindow")]) {
                    id controller = [candidate performSelector:@selector(windowController)];
                    id tab = [controller performSelector:@selector(selectedTabController)];
                    id profile = [tab performSelector:@selector(profile)];
                    if (name && [[profile valueForKey:@"name"] isEqual:name])
                        [candidate performClose:nil];
                }
            }
            [windows release];
            all = [manager valueForKey:@"profiles"];
            for (i = 0; i < [all count]; i++)
                if ([[[all objectAtIndex:i] valueForKey:@"name"] isEqual:name]) {
                    SEL selector = sel_getUid("removeObjectFromProfilesAtIndex:");
                    ((void (*)(id, SEL, unsigned))[manager methodForSelector:selector])(
                        manager, selector, i);
                    break;
                }
            [snowRenderingTestProfile release];
            snowRenderingTestProfile = nil;
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"prefs-open-selected"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            [controller performSelector:@selector(tableViewDoubleClick:)
                             withObject:[controller valueForKey:@"profilesTableView"]];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"prefs-set-color"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            char path[128];
            float red, green, blue;
            NSColorWell *well;
            if (sscanf([payload cString], "%127s %f %f %f", path, &red, &green, &blue) != 4)
                [NSException raise:NSInvalidArgumentException
                            format:@"Expected binding and RGB color"];
            well = (NSColorWell *)snowBoundControl([[controller window] contentView],
                                                   [NSString stringWithCString:path], nil);
            if (![well isKindOfClass:[NSColorWell class]])
                [NSException raise:NSInvalidArgumentException format:@"No color well for %s", path];
            [well setColor:[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1]];
            [well sendAction:[well action] to:[well target]];
            snowBoundControl([[controller window] contentView], nil, reply);
        } else if ([operation isEqual:@"render-state"]) {
            NSArray *windows = [NSApp windows];
            for (i = 0; i < [windows count]; i++) {
                NSWindow *candidate = [windows objectAtIndex:i];
                if ([candidate isVisible] &&
                    [candidate isKindOfClass:NSClassFromString(@"TTWindow")]) {
                    id controller = [candidate performSelector:@selector(windowController)];
                    id tab = [controller performSelector:@selector(selectedTabController)];
                    id profile = [tab performSelector:@selector(profile)];
                    id terminal = snowFindTerminal([candidate contentView]);
                    id viewProfile = [terminal performSelector:@selector(profile)];
                    [reply
                        appendFormat:@"window=%@ profile=%x %@ parent=%@ viewProfile=%x %@\n",
                                     NSStringFromRect([candidate frame]), (unsigned)profile,
                                     [profile valueForKey:@"name"],
                                     [[profile valueForKey:@"parentProfile"] valueForKey:@"name"],
                                     (unsigned)viewProfile, [viewProfile valueForKey:@"name"]];
                    [reply appendFormat:@"text=%@ background=%@ cachedBackground=%@ font=%@\n",
                                        [viewProfile valueForKey:@"TextColor"],
                                        [viewProfile valueForKey:@"BackgroundColor"],
                                        [terminal valueForKey:@"_currentBackgroundColor"],
                                        [viewProfile valueForKey:@"Font"]];
                }
            }
        } else if ([operation isEqual:@"prefs-copy-cell"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            NSTableView *table = [controller valueForKey:@"profilesTableView"];
            id original = [[[table tableColumns] objectAtIndex:0] dataCell];
            id duplicate = [original copyWithZone:NULL];
            const char *children[] = {"_titleCell", "_defaultCell", "_thumbnailCell"};
            if (!duplicate || duplicate == original || [duplicate class] != [original class])
                [NSException raise:NSInternalInconsistencyException
                            format:@"Invalid theme cell copy"];
            for (i = 0; i < 3; i++) {
                Ivar ivar = class_getInstanceVariable([original class], children[i]);
                id before = *(id *)((char *)original + ivar->ivar_offset);
                id after = *(id *)((char *)duplicate + ivar->ivar_offset);
                if (!after || before == after)
                    [NSException raise:NSInternalInconsistencyException
                                format:@"Theme cell copy shares %s", children[i]];
            }
            [duplicate release];
            [reply appendString:@"OK independent theme cell and child cells"];
        } else if ([operation isEqual:@"prefs-profiles"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            id profiles = [controller valueForKey:@"profilesController"];
            NSArray *all = [profiles valueForKey:@"arrangedObjects"];
            for (i = 0; i < [all count]; i++)
                [reply appendFormat:@"%@\n", [[all objectAtIndex:i] valueForKey:@"name"]];
        } else if ([operation isEqual:@"prefs-select"] || [operation isEqual:@"prefs-select-row"] ||
                   [operation isEqual:@"prefs-click"] || [operation isEqual:@"prefs-click-index"] ||
                   [operation isEqual:@"prefs-double-click"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            id profiles = [controller valueForKey:@"profilesController"];
            NSArray *all = [profiles valueForKey:@"arrangedObjects"];
            id expected;
            if ([operation isEqual:@"prefs-click-index"])
                i = [payload intValue];
            else
                for (i = 0; i < [all count]; i++)
                    if ([[[all objectAtIndex:i] valueForKey:@"name"] isEqual:payload])
                        break;
            if (i >= [all count])
                [NSException raise:NSInvalidArgumentException format:@"No profile %@", payload];
            expected = [[all objectAtIndex:i] valueForKey:@"name"];
            if (![operation isEqual:@"prefs-select"]) {
                NSTableView *table = [controller valueForKey:@"profilesTableView"];
                [table scrollRowToVisible:i];
                if ([operation isEqual:@"prefs-select-row"])
                    [table selectRow:i byExtendingSelection:NO];
                else {
                    NSWindow *preferences = [controller window];
                    NSRect row = [table rectOfRow:i];
                    NSPoint point = [table convertPoint:NSMakePoint(NSMidX(row), NSMidY(row))
                                                 toView:nil];
                    int clicks = [operation isEqual:@"prefs-double-click"] ? 2 : 1;
                    NSEvent *down, *up;
                    [NSApp activateIgnoringOtherApps:YES];
                    [preferences makeKeyAndOrderFront:nil];
                    down = [NSEvent mouseEventWithType:NSLeftMouseDown
                                              location:point
                                         modifierFlags:0
                                             timestamp:0
                                          windowNumber:[preferences windowNumber]
                                               context:[NSDPSContext currentContext]
                                           eventNumber:1
                                            clickCount:clicks
                                              pressure:1];
                    up = [NSEvent mouseEventWithType:NSLeftMouseUp
                                            location:point
                                       modifierFlags:0
                                           timestamp:0
                                        windowNumber:[preferences windowNumber]
                                             context:[NSDPSContext currentContext]
                                         eventNumber:2
                                          clickCount:clicks
                                            pressure:0];
                    [NSApp postEvent:up atStart:YES];
                    [NSApp sendEvent:down];
                }
            } else
                [profiles
                    setSelectionIndexes:[NSClassFromString(@"NSIndexSet") indexSetWithIndex:i]];
            {
                id selected = [[profiles valueForKey:@"selection"] valueForKey:@"name"];
                if (![selected isEqual:expected])
                    [NSException raise:NSInternalInconsistencyException
                                format:@"Selected %@ instead of %@", selected, expected];
                [reply appendFormat:@"OK selected=%@", selected];
            }
        } else if ([operation isEqual:@"prefs-pane"] ||
                   [operation isEqual:@"prefs-settings-pane"]) {
            id controller = [NSClassFromString(@"TTAppPrefsController")
                performSelector:@selector(sharedPreferencesController)];
            id tabs = [controller valueForKey:@"tabView"];
            if ([operation isEqual:@"prefs-settings-pane"]) {
                NSArray *children = [[[tabs tabViewItemAtIndex:1] view] subviews];
                tabs = nil;
                for (i = 0; i < [children count]; i++)
                    if ([[children objectAtIndex:i]
                            isKindOfClass:NSClassFromString(@"NSTabView")]) {
                        tabs = [children objectAtIndex:i];
                        break;
                    }
                if (!tabs)
                    [NSException raise:NSInvalidArgumentException
                                format:@"No Settings pane buttons"];
            }
            [tabs selectTabViewItemAtIndex:[payload intValue]];
            [reply appendFormat:@"OK selected=%@", [[tabs selectedTabViewItem] label]];
        } else if ([operation isEqual:@"front"]) {
            [NSApp activateIgnoringOtherApps:YES];
            [window makeKeyAndOrderFront:nil];
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"text"]) {
            if (!window)
                [NSException raise:NSInvalidArgumentException format:@"No terminal window"];
            [window makeKeyAndOrderFront:nil];
            for (i = 0; i < [payload length]; i++) {
                unichar character = [payload characterAtIndex:i];
                NSString *text;
                NSEvent *event;
                unsigned flags;
                if (character == '\n')
                    character = '\r';
                text = [NSString stringWithCharacters:&character length:1];
                flags = (character >= 0xf700 && character <= 0xf747) ? NSFunctionKeyMask : 0;
                event = [NSEvent keyEventWithType:NSKeyDown
                                         location:NSZeroPoint
                                    modifierFlags:flags
                                        timestamp:0
                                     windowNumber:[window windowNumber]
                                          context:[NSDPSContext currentContext]
                                       characters:text
                      charactersIgnoringModifiers:text
                                        isARepeat:NO
                                          keyCode:0];
                [NSApp sendEvent:event];
                event = [NSEvent keyEventWithType:NSKeyUp
                                         location:NSZeroPoint
                                    modifierFlags:flags
                                        timestamp:0
                                     windowNumber:[window windowNumber]
                                          context:[NSDPSContext currentContext]
                                       characters:text
                      charactersIgnoringModifiers:text
                                        isARepeat:NO
                                          keyCode:0];
                [NSApp sendEvent:event];
            }
            [reply appendString:@"OK"];
        } else if ([operation isEqual:@"action"] || [operation isEqual:@"app-action"]) {
            [reply appendFormat:@"sent=%d",
                                [NSApp sendAction:NSSelectorFromString(payload)
                                               to:[operation isEqual:@"app-action"] ? NSApp : nil
                                             from:nil]];
        } else
            [NSException raise:NSInvalidArgumentException
                        format:@"Unknown test operation %@", operation];
    NS_HANDLER
        [reply appendFormat:@"ERROR %@", [localException reason]];
    NS_ENDHANDLER
    gettimeofday(&finished, NULL);
    fprintf(stderr, "SNOW request %s %s %.3fs\n", [identifier cString], [operation cString],
            (finished.tv_sec - started.tv_sec) + (finished.tv_usec - started.tv_usec) / 1000000.0);
    [[reply dataUsingEncoding:NSUTF8StringEncoding]
        writeToFile:[snowTestDirectory stringByAppendingPathComponent:@"test.response"]
         atomically:YES];
}
@end
void SnowStartTestControl(void) {
    NSTimer *timer;
    snowTestDirectory = [[[NSFileManager defaultManager] currentDirectoryPath] copy];
    timer = [NSTimer timerWithTimeInterval:0.1
                                    target:[SnowTestControl class]
                                  selector:@selector(poll:)
                                  userInfo:nil
                                   repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    /* A callback that opens a modal panel keeps its default-mode timer
     * busy. A distinct timer must handle requests inside the modal loop. */
    timer = [NSTimer timerWithTimeInterval:0.1
                                    target:[SnowTestControl class]
                                  selector:@selector(poll:)
                                  userInfo:nil
                                   repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
}
