/* A reference-counted URL fixture; the native Foundation predates NSURL. */
static unsigned snowLiveTestURLs;
@interface NSURL : NSObject {
    NSString *value;
}
- initWithString:(NSString *)string;
- (NSString *)absoluteString;
@end
@implementation NSURL
- initWithString:(NSString *)string {
    self = [super init];
    value = [string copy];
    snowLiveTestURLs++;
    return self;
}
- (NSString *)absoluteString {
    return value;
}
- (void)dealloc {
    snowLiveTestURLs--;
    [value release];
    [super dealloc];
}
@end
