/* Timer-driven Cocoa animation, including controllers with hidden tab strips. */
@interface NSObject (SnowAnimationDelegate)
- (BOOL)animationShouldStart:(id)animation;
- (void)animationDidEnd:(id)animation;
- (void)animationDidStop:(id)animation;
@end
@interface NSAnimation : NSObject {
    double snowDuration, snowStarted;
    float snowProgress, snowRate;
    int snowCurve, snowBlockingMode;
    id snowAnimationDelegate;
    NSTimer *snowAnimationTimer;
}
- initWithDuration:(double)duration animationCurve:(int)curve;
- (void)setCurrentProgress:(float)progress;
- (float)currentProgress;
- (float)currentValue;
- (void)stopAnimation;
@end
@implementation NSAnimation
- initWithDuration:(double)duration animationCurve:(int)curve {
    self = [super init];
    snowDuration = duration;
    snowCurve = curve;
    snowRate = 30;
    return self;
}
- (void)setDuration:(double)duration {
    snowDuration = duration;
}
- (double)duration {
    return snowDuration;
}
- (void)setFrameRate:(float)rate {
    snowRate = rate;
}
- (float)frameRate {
    return snowRate;
}
- (void)setAnimationCurve:(int)curve {
    snowCurve = curve;
}
- (int)animationCurve {
    return snowCurve;
}
- (void)setAnimationBlockingMode:(int)mode {
    snowBlockingMode = mode;
}
- (int)animationBlockingMode {
    return snowBlockingMode;
}
- (void)setDelegate:(id)delegate {
    snowAnimationDelegate = delegate;
}
- (id)delegate {
    return snowAnimationDelegate;
}
- (BOOL)isAnimating {
    return snowAnimationTimer != nil;
}
- (void)setCurrentProgress:(float)progress {
    snowProgress = progress < 0 ? 0 : (progress > 1 ? 1 : progress);
}
- (float)currentProgress {
    return snowProgress;
}
- (float)currentValue {
    float p = snowProgress;
    if (snowCurve == 0)
        return p * p * (3 - 2 * p);
    if (snowCurve == 1)
        return p * p;
    if (snowCurve == 2)
        return 1 - (1 - p) * (1 - p);
    return p;
}
- (void)snowAnimationStep:(id)sender {
    float progress = snowDuration <= 0
                         ? 1
                         : ([NSDate timeIntervalSinceReferenceDate] - snowStarted) / snowDuration;
    [self setCurrentProgress:progress];
    if (progress >= 1) {
        [snowAnimationTimer invalidate];
        [snowAnimationTimer release];
        snowAnimationTimer = nil;
        if ([snowAnimationDelegate respondsToSelector:@selector(animationDidEnd:)])
            [snowAnimationDelegate animationDidEnd:self];
    }
}
- (void)startAnimation {
    float rate = snowRate > 0 && snowRate <= 240 ? snowRate : 30;
    if (snowAnimationTimer)
        return;
    if ([snowAnimationDelegate respondsToSelector:@selector(animationShouldStart:)] &&
        ![snowAnimationDelegate animationShouldStart:self])
        return;
    snowStarted = [NSDate timeIntervalSinceReferenceDate];
    [self setCurrentProgress:0];
    snowAnimationTimer = [[NSTimer timerWithTimeInterval:1.0 / rate
                                                  target:self
                                                selector:@selector(snowAnimationStep:)
                                                userInfo:nil
                                                 repeats:YES] retain];
    [[NSRunLoop currentRunLoop] addTimer:snowAnimationTimer forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:snowAnimationTimer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:snowAnimationTimer forMode:NSModalPanelRunLoopMode];
    if (snowBlockingMode == 0)
        while (snowAnimationTimer)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
- (void)stopAnimation {
    if (!snowAnimationTimer)
        return;
    [snowAnimationTimer invalidate];
    [snowAnimationTimer release];
    snowAnimationTimer = nil;
    if ([snowAnimationDelegate respondsToSelector:@selector(animationDidStop:)])
        [snowAnimationDelegate animationDidStop:self];
}
- (void)dealloc {
    [snowAnimationTimer invalidate];
    [snowAnimationTimer release];
    [super dealloc];
}
@end
