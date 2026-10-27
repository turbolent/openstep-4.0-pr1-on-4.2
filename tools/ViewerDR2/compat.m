/* Run DR2 Viewer as a separate application beside the native Workspace. */
#define VIEWER_DR2 1
#include "common/viewer.m"
#include <sys/vfs.h>

extern void DR2InitializeFileAttributes(void);

enum {
    MinimumLowSpace = 100 * 1024,
    MaximumLowSpace = 2 * 1024 * 1024,
    LowSpaceDivisor = 20
};

static long long freeSpace(id receiver, SEL selector, BOOL *low,
                          NSString *directory, NSString *file) {
    NSString *path = file ? [directory stringByAppendingPathComponent:file] : directory;
    struct statfs volume;
    long long available, threshold;
    if (low) *low = NO;
    /* The selection can still name a just-recycled file until the next redraw.
     * Query its containing filesystem instead of briefly reporting zero space. */
    while (statfs([path cString], &volume)) {
        NSString *parent;
        if (errno != ENOENT && errno != ENOTDIR) return 0;
        parent = [path stringByDeletingLastPathComponent];
        if (![parent length] || [parent isEqual:path]) return 0;
        path = parent;
    }
    available = (long long)volume.f_bavail * volume.f_bsize;
    threshold = (long long)volume.f_blocks * volume.f_bsize / LowSpaceDivisor;
    if (threshold < MinimumLowSpace) threshold = MinimumLowSpace;
    if (threshold > MaximumLowSpace) threshold = MaximumLowSpace;
    if (low) *low = available < threshold;
    return available;
}

static IMP originalRefreshHeuristic;
static BOOL refreshingCompletedOperation;

static BOOL shouldRefreshWindow(id window, SEL selector) {
    if (refreshingCompletedOperation) return YES;
    return ((BOOL (*)(id, SEL))originalRefreshHeuristic)(window, selector);
}

void DR2RefreshViewerAfterFileOperation(void) {
    BOOL wasRefreshing = refreshingCompletedOperation;
    /* DR2 defers background refreshes while the pointer is over a busy window.
     * A completed user operation should update its result without that wait. */
    refreshingCompletedOperation = YES;
    NS_DURING
        [[NSNotificationCenter defaultCenter]
            postNotificationName:@"ViewerNodeStructureChanged" object:nil];
    NS_HANDLER
        refreshingCompletedOperation = wasRefreshing;
        [localException raise];
    NS_ENDHANDLER
    refreshingCompletedOperation = wasRefreshing;
}

void DR2InitializeViewer(void) {
    Method method;
    DR2InitializeFileAttributes();
    method = class_getInstanceMethod(NSClassFromString(@"Device"),
        @selector(freeSpaceAndLow:forDir:file:));
    method->method_imp = (IMP)freeSpace;
    method = class_getInstanceMethod(NSClassFromString(@"WMWindow"),
        @selector(heuristicForRealUpdate));
    originalRefreshHeuristic = method->method_imp;
    method->method_imp = (IMP)shouldRefreshWindow;
}

@interface NSObject (ViewerDR2Selection)
- selectionOwner;
- (void)selectParentFolder:(id)sender;
@end
@implementation Viewer (DR2ParentFolder)
- (void)selectParentFolder:(id)sender {
    id owner = [self selectionOwner];
    if (owner != self && [owner respondsToSelector:_cmd])
        [owner selectParentFolder:sender];
}
@end

void NSShowSystemInfoPanel(void) {
    NSRunAlertPanel(@"Viewer DR2", @"Rhapsody DR2 Viewer on OPENSTEP 4.2",
                   @"OK", nil, nil);
}
