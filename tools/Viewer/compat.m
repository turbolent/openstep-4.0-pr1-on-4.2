/* PR1-specific tooltip guard and shared standalone Viewer support. */
#import <AppKit/AppKit.h>

/* Native tooltips replace this callback. Keep the guard in the app module so
 * dyld binds it before PR1's help module imports the removed NSHelpPanel. */
@interface NSViewBubbleHelper : NSObject
@end
@implementation NSViewBubbleHelper (PR142Compatibility)
+ (void)displayHelpText { }
@end

#include "../common/viewer.m"
