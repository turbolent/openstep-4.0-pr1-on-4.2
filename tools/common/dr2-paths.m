/* Translate DR2 directory searches to the OPENSTEP filesystem layout. */
#import <AppKit/AppKit.h>

enum {
    DR2ApplicationDirectory = 1,
    DR2DeveloperApplicationDirectory = 3,
    DR2LibraryDirectory = 5,
    DR2DeveloperDirectory = 6,
    DR2DocumentationDirectory = 8,
    DR2AllApplications = 100,
    DR2AllLibraries = 101,
    SearchDomainCount = 4
};

NSArray *NSSearchPathForDirectoriesInDomains(unsigned directory, unsigned domains,
                                             BOOL expand) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *bases[SearchDomainCount] = {@"~", @"/LocalLibrary", @"/Network/Library",
                                          @"/NextLibrary"};
    NSString *path;
    unsigned index;
    for (index = 0; index < SearchDomainCount; index++) {
        if (!(domains & (1 << index)))
            continue;
        path = bases[index];
        if (directory == DR2LibraryDirectory || directory == DR2AllLibraries) {
            if (index == 0)
                path = @"~/Library";
        } else if (directory == DR2ApplicationDirectory ||
                   directory == DR2AllApplications) {
            path = index == 0   ? @"~/Apps"
                   : index == 1 ? @"/LocalApps"
                   : index == 2 ? @"/Network/Apps"
                                : @"/NextApps";
        } else if (directory == DR2DeveloperDirectory) {
            path = @"/NextDeveloper";
        } else if (directory == DR2DeveloperApplicationDirectory) {
            path = @"/NextDeveloper/Apps";
        } else if (directory == DR2DocumentationDirectory) {
            path = [path stringByAppendingPathComponent:@"Documentation"];
        } else
            continue;
        [paths addObject:expand ? [path stringByExpandingTildeInPath] : path];
    }
    return paths;
}
