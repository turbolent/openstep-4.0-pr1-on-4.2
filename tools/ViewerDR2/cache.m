/* Generate an empty application registry in OPENSTEP's serialization format. */
#import <Foundation/Foundation.h>

int main(int argc, char **argv) {
    NSAutoreleasePool *pool;
    NSData *data;
    BOOL saved;
    if (argc != 2) return 2;
    pool = [[NSAutoreleasePool alloc] init];
    data = [NSSerializer serializePropertyList:[NSDictionary dictionary]];
    saved = [data writeToFile:[NSString stringWithCString:argv[1]] atomically:YES];
    [pool release];
    return saved ? 0 : 1;
}
