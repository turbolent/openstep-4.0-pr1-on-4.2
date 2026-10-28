/* Exercise edits through native control actions, without an Apple binary. */
#include <assert.h>
@interface SnowControlAction : NSObject {
  @public
    unsigned changes;
}
- (void)changed:(id)sender;
@end
@implementation SnowControlAction
- (void)changed:(id)sender {
    changes++;
}
@end
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSMutableDictionary *model = [NSMutableDictionary dictionary];
    NSButton *button;
    NSColorWell *well;
    NSColor *color = [NSColor blueColor];
    SnowControlAction *action = [[SnowControlAction alloc] init];
    [NSApplication sharedApplication];
    SnowInitializeFoundation();
    SnowInitializeFormatting();
    SnowInitializeBindings();
    [model setObject:[NSNumber numberWithInt:0] forKey:@"flag"];
    button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
    [button setButtonType:NSSwitchButton];
    [button setTarget:action];
    [button bind:@"value" toObject:model withKeyPath:@"flag" options:nil];
    [button performClick:nil];
    assert([[model objectForKey:@"flag"] boolValue]);
    [button unbind:@"value"];
    assert([button action] == NULL && [button target] == action);
    [button setAction:@selector(changed:)];
    [button bind:@"value" toObject:model withKeyPath:@"flag" options:nil];
    [button performClick:nil];
    assert(![[model objectForKey:@"flag"] boolValue] && action->changes == 1);
    [button unbind:@"value"];
    assert([button action] == @selector(changed:) && [button target] == action);
    [button release];
    [model setObject:[NSColor blackColor] forKey:@"color"];
    well = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
    [well bind:@"value" toObject:model withKeyPath:@"color" options:nil];
    [well setColor:color];
    [well sendAction:[well action] to:[well target]];
    assert([[model objectForKey:@"color"] isEqual:color]);
    [well unbind:@"value"];
    assert([well action] == NULL && [well target] == nil);
    [well release];
    [action release];
    [pool release];
    puts("PASS native checkbox and color-well edits, existing actions, and unbinding");
    return 0;
}
