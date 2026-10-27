/* Bounded attributed-text history for Compose; 4.2 has no text undo API. */
#import <AppKit/AppKit.h>
#import <objc/objc-class.h>

enum {
    MaximumUndoStates = 100
};
static NSMutableDictionary *histories;
static IMP originalComposeDealloc;

@interface DR2TextHistory : NSObject {
    NSTextView *view;
    NSAttributedString *previous;
    NSMutableArray *undoStates;
    NSMutableArray *redoStates;
    BOOL restoring;
}
- initWithView:(NSTextView *)textView;
- (void)changed:(NSNotification *)notification;
- (void)restoreFrom:(NSMutableArray *)source to:(NSMutableArray *)destination;
- (void)undo;
- (void)redo;
- (BOOL)canUndo;
- (BOOL)canRedo;
@end

static NSValue *historyKey(id view) {
    return [NSValue valueWithPointer:view];
}
static DR2TextHistory *historyForView(id view) {
    return [histories objectForKey:historyKey(view)];
}
static void composeDealloc(id receiver, SEL selector) {
    [histories removeObjectForKey:historyKey(receiver)];
    ((void (*)(id, SEL))originalComposeDealloc)(receiver, selector);
}

@implementation DR2TextHistory
+ (void)load {
    Method method = class_getInstanceMethod(NSClassFromString(@"ComposeText"), @selector(dealloc));
    if (!method)
        return;
    originalComposeDealloc = method->method_imp;
    method->method_imp = (IMP)composeDealloc;
}
- initWithView:(NSTextView *)textView {
    self = [super init];
    view = textView;
    previous = [[view textStorage] copy];
    undoStates = [[NSMutableArray alloc] init];
    redoStates = [[NSMutableArray alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(changed:)
                                                 name:NSTextDidChangeNotification
                                               object:view];
    return self;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [previous release];
    [undoStates release];
    [redoStates release];
    [super dealloc];
}
- (void)changed:(NSNotification *)notification {
    NSAttributedString *current;
    if (restoring)
        return;
    current = [[view textStorage] copy];
    if (![current isEqualToAttributedString:previous]) {
        [undoStates addObject:previous];
        if ([undoStates count] > MaximumUndoStates)
            [undoStates removeObjectAtIndex:0];
        [redoStates removeAllObjects];
        [previous release];
        previous = current;
    } else
        [current release];
}
- (void)restoreFrom:(NSMutableArray *)source to:(NSMutableArray *)destination {
    NSAttributedString *replacement;
    NSTextStorage *storage = [view textStorage];
    NSRange selection = [view selectedRange];
    unsigned length;
    if (![source count]) {
        NSBeep();
        return;
    }
    replacement = [[source lastObject] retain];
    if (![view shouldChangeTextInRange:NSMakeRange(0, [storage length])
                     replacementString:[replacement string]]) {
        [replacement release];
        return;
    }
    [destination addObject:previous];
    [source removeLastObject];
    restoring = YES;
    [storage beginEditing];
    [storage setAttributedString:replacement];
    [storage endEditing];
    length = [storage length];
    if (selection.location > length)
        selection.location = length;
    selection.length = 0;
    [view setSelectedRange:selection];
    [view didChangeText];
    [view scrollRangeToVisible:selection];
    restoring = NO;
    [previous release];
    previous = replacement;
}
- (void)undo {
    [self restoreFrom:undoStates to:redoStates];
}
- (void)redo {
    [self restoreFrom:redoStates to:undoStates];
}
- (BOOL)canUndo {
    return [undoStates count] > 0;
}
- (BOOL)canRedo {
    return [redoStates count] > 0;
}
@end

@interface NSTextView (DR2Undo)
- (void)setAllowsUndo:(BOOL)flag;
- (BOOL)allowsUndo;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
@end
@implementation NSTextView (DR2Undo)
- (void)setAllowsUndo:(BOOL)flag {
    if (!flag)
        [histories removeObjectForKey:historyKey(self)];
    else if (!historyForView(self)) {
        DR2TextHistory *history = [[DR2TextHistory alloc] initWithView:self];
        if (!histories)
            histories = [[NSMutableDictionary alloc] init];
        [histories setObject:history forKey:historyKey(self)];
        [history release];
    }
}
- (BOOL)allowsUndo {
    return historyForView(self) != nil;
}
- (void)undo:(id)sender {
    [historyForView(self) undo];
}
- (void)redo:(id)sender {
    [historyForView(self) redo];
}
@end

@interface ComposeText : NSTextView
@end
@implementation ComposeText (DR2UndoValidation)
- (BOOL)validateMenuItem:(id<NSMenuItem>)item {
    SEL action = [item action];
    if (action == @selector(undo:))
        return [historyForView(self) canUndo];
    if (action == @selector(redo:))
        return [historyForView(self) canRedo];
    return [super validateMenuItem:item];
}
@end
