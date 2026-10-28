/* Private connection between the standalone DR2 Workspace and Viewer ports. */
#ifndef DR2_VIEWER_SERVICE_H
#define DR2_VIEWER_SERVICE_H
#import <Foundation/Foundation.h>
#include <libc.h>

enum {
    DR2ViewerServiceVersion = 1
};

static NSString *DR2ViewerServiceName(void) {
    return [NSString stringWithFormat:@"ViewerDR2.Desktop.%u", (unsigned)getuid()];
}

@protocol DR2ViewerService
- (BOOL)showProcesses;
- (BOOL)openPath:(bycopy NSString *)path;
- (BOOL)revealPath:(bycopy NSString *)path;
@end
#endif
