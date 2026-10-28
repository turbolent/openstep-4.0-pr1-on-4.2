/* Build generated projects with OPENSTEP's installed development tools. */
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>

@interface DR2ProjectBuilderEnvironment : NSObject
@end
@implementation DR2ProjectBuilderEnvironment
+ (void)load {
    extern char **environ;
    static char makefiles[] = "MAKEFILEPATH=/NextDeveloper/Makefiles";
    static const char key[] = "MAKEFILEPATH=";
    char **environment;
    unsigned count = 0, index, copied = 0;
    while (environ[count])
        count++;
    environment = malloc((count + 2) * sizeof(*environment));
    if (!environment)
        exit(1);
    for (index = 0; index < count; index++)
        if (strncmp(environ[index], key, sizeof(key) - 1))
            environment[copied++] = environ[index];
    environment[copied++] = makefiles;
    environment[copied] = NULL;
    environ = environment;
}
@end
