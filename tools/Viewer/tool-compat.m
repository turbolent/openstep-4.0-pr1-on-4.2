#import <Foundation/Foundation.h>

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
    [domains insertObject:@"Viewer" atIndex:0];
    [defaults setSearchList:domains];
    [domains release];
    [defaults registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
        @"/bin/rm", @"rm", @"/usr/bin/gnutar", @"tar",
        @"/usr/ucb/compress", @"compress", @"/usr/ucb/uncompress", @"uncompress",
        @"Yes", @"AlwaysTarForCompress", nil]];
    [pool release];
    return self;
}
@end
