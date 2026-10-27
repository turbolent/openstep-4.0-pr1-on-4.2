#import <AppKit/AppKit.h>
#import <objc/objc-class.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSString *NSFilenamePboardType = @"NeXT filename pasteboard type";
NSString *NSViewFrameChangedNotification = nil;

/* The executable references this removed class for voice-message filenames.
 * A normal dyld launch requires its class symbol even if recording is unused. */
@interface NSUserAccount : NSObject
+ currentAccount;
- (NSString *)accountName;
@end
@implementation NSUserAccount
+ currentAccount {
    static NSUserAccount *account = nil;
    if (!account)
        account = [[self alloc] init];
    return account;
}
- (NSString *)accountName {
    return NSUserName();
}
@end

static IMP originalMailInit = 0;
static IMP originalMailReady = 0;

@interface NSObject (MailViewerMethods)
+ allMessageViewers;
+ sharedInstance;
- (NSString *)defaultMailDirectory;
+ storeForPath:(NSString *)path;
- (void)showMailboxesPanel:(id)sender;
- (void)setShowAllHeaders:(BOOL)flag;
- (BOOL)isShowingAllHeaders;
@end

static void MailReady(id receiver, SEL selector, NSNotification *notification) {
    ((void (*)(id, SEL, id))originalMailReady)(receiver, selector, notification);
    [[NSApp mainMenu] setTitle:@"MailViewer PR1"];
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"NXAutoLaunch"]) {
        if (![[NSClassFromString(@"MessageViewer") allMessageViewers] count])
            [receiver showMailboxesPanel:nil];
        [NSApp activateIgnoringOtherApps:YES];
    }
}
static id MailInit(id receiver, SEL selector) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *domains = [[defaults searchList] mutableCopy];
    if (![domains containsObject:@"Message"]) {
        unsigned int index = [domains indexOfObject:NSGlobalDomain];
        if (index == NSNotFound)
            index = [domains count];
        [domains insertObject:@"Message" atIndex:index];
        [defaults setSearchList:domains];
    }
    [domains release];
    return ((id(*)(id, SEL))originalMailInit)(receiver, selector);
}

@interface MailViewerCompatibility : NSObject
@end
@implementation MailViewerCompatibility
+ (void)load {
    Method init = class_getInstanceMethod(NSClassFromString(@"MailApp"), @selector(init));
    Method ready = class_getInstanceMethod(NSClassFromString(@"MailApp"),
                                           @selector(applicationDidFinishLaunching:));
    NSViewFrameChangedNotification = NSViewFrameDidChangeNotification;
    originalMailInit = init->method_imp;
    init->method_imp = (IMP)MailInit;
    originalMailReady = ready->method_imp;
    ready->method_imp = (IMP)MailReady;
}
@end

@interface NSTextView (MailViewerTextCompatibility)
- (void)setText:(NSString *)text range:(NSRange)range;
@end
@implementation NSTextView (MailViewerTextCompatibility)
- (void)setText:(NSString *)text range:(NSRange)range {
    NSTextStorage *storage = [self textStorage];
    NSDictionary *attributes = [self typingAttributes];
    [storage beginEditing];
    [storage replaceCharactersInRange:range withString:text];
    if ([text length] && attributes)
        [storage setAttributes:attributes range:NSMakeRange(range.location, [text length])];
    [storage endEditing];
}
@end

@interface TextDocumentViewer : NSObject
@end
@implementation TextDocumentViewer (MailViewerHeadersCompatibility)
- (void)toggleHeaders:(id)sender {
    [self setShowAllHeaders:![self isShowingAllHeaders]];
}
@end

@interface MailApp : NSApplication
@end
@implementation MailApp (MailViewerServicesCompatibility)
- (void)registerServiceProvider:(id)provider withName:(NSString *)name {
    [self setServicesProvider:provider];
}
@end

static BOOL MailDirectory(NSString *path) {
    NSFileManager *files = [NSFileManager defaultManager];
    BOOL directory = NO;
    if ([files fileExistsAtPath:path isDirectory:&directory])
        return directory;
    if (![path length] || [path isEqual:@"/"])
        return NO;
    if (!MailDirectory([path stringByDeletingLastPathComponent]))
        return NO;
    return [files createDirectoryAtPath:path attributes:nil];
}

/* PR1 ignores the create argument and silently refuses to save the first draft. */
@implementation MailApp (MailViewerDraftsCompatibility)
- draftsStore:(BOOL)create {
    NSString *directory = [[NSClassFromString(@"Defaults") sharedInstance] defaultMailDirectory];
    NSString *name = [[NSBundle mainBundle] localizedStringForKey:@"Drafts.mbox"
                                                            value:@"Drafts.mbox"
                                                            table:@"Paths"];
    NSString *path = [[directory stringByAppendingPathComponent:name] stringByStandardizingPath];
    NSFileManager *files = [NSFileManager defaultManager];
    if (create && ![files fileExistsAtPath:path]) {
        NSString *mbox;
        int descriptor;
        if (!MailDirectory(path)) {
            NSRunAlertPanel(@"Save Draft", @"Cannot create %@.", @"OK", nil, nil, path);
            return nil;
        }
        mbox = [path stringByAppendingPathComponent:@"mbox"];
        descriptor = open([mbox fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (descriptor >= 0)
            close(descriptor);
        else if (errno != EEXIST) {
            NSRunAlertPanel(@"Save Draft", @"Cannot create %@.", @"OK", nil, nil, mbox);
            return nil;
        }
    }
    return [files fileExistsAtPath:path] ? [NSClassFromString(@"MessageStore") storeForPath:path]
                                         : nil;
}
@end

/* Native tooltips replace this callback. Keep the guard in the app module so
 * dyld binds it before PR1's help module imports the removed NSHelpPanel. */
@interface NSViewBubbleHelper : NSObject
@end
@implementation NSViewBubbleHelper (MailViewer42Compatibility)
+ (void)displayHelpText {
}
@end
