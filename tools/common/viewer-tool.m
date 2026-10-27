#import <Foundation/Foundation.h>

#ifdef VIEWER_DR2
extern void DR2InitializeFileAttributes(void);
#endif

@interface NSConnection (ViewerToolBootstrap)
+ newSlave;
@end

@interface ViewerTool : NSObject {
    NSConnection *connection;
}
@end

extern id NSTool;

@implementation ViewerTool (PR142Compatibility)
- init {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSUserDefaults *defaults;
    NSMutableArray *domains;
    self = [super init];
    connection = [NSConnection newSlave];
    if (!connection) {
        [self release];
        [pool release];
        return nil;
    }
    [connection setRootObject:self];
    NSTool = self;
    defaults = [NSUserDefaults standardUserDefaults];
    /* Foundation 4.2 returns an immutable preferences search list. */
    domains = [[defaults searchList] mutableCopy];
#ifdef VIEWER_DR2
    [domains insertObject:@"ViewerDR2" atIndex:0];
#else
    [domains insertObject:@"Viewer" atIndex:0];
#endif
    [defaults setSearchList:domains];
    [domains release];
    [defaults
        registerDefaults:[NSDictionary
                             dictionaryWithObjectsAndKeys:@"/bin/rm", @"rm", @"/usr/bin/gnutar",
                                                          @"tar", @"/usr/ucb/compress", @"compress",
                                                          @"/usr/ucb/uncompress", @"uncompress",
                                                          @"Yes", @"AlwaysTarForCompress", nil]];
#ifdef VIEWER_DR2
    DR2InitializeFileAttributes();
#endif
    [pool release];
    return self;
}
@end
