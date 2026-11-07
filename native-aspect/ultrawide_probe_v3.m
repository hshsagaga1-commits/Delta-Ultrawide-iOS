// Delta Native Ultrawide V3: experimental geometry matching for game view.
// Keeps V2 aspect-preserving CAMetalLayer hook; fits actual game UIView to
// requested ultrawide aspect. Physical screen cannot become 32:9.
// This does not spoof iOS UIScreen dimensions or guarantee camera FOV.
#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <math.h>
#import <stdarg.h>

static void (*oldDrawable)(id, SEL, CGSize) = NULL;
static void (*oldFrame)(id, SEL, CGRect) = NULL;
static __weak UIView *gameView = nil;
static __weak CAMetalLayer *lastLayer = nil;
static CGSize lastRequested = {0,0};
static NSInteger mode = 0, logs = 0;
static BOOL editingFrame = NO;

static void note(NSString *fmt, ...) {
    if (logs >= 65) return; logs++;
    va_list args; va_start(args, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[DeltaAspectV3] %@",line);
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!dir) return;
    NSString *path = [dir stringByAppendingPathComponent:@"DeltaAspectV3.log"];
    NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [data writeToFile:path atomically:YES];
    } else {
        NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
        if(file) { @try { [file seekToEndOfFile]; [file writeData:data]; } @catch (NSException *e) {} [file closeFile]; }
    }
}
static double aspect(void) {return mode==2 ? 32.0/9.0 : 21.0/9.0;}

static CGRect fitRect(UIView *view, CGRect given) {
    UIView *parent=view.superview;
    if(!parent || mode==0) return given;
    CGRect b=parent.bounds;
    CGFloat w=CGRectGetWidth(b), h=CGRectGetHeight(b);
    if (!isfinite(w) || !isfinite(h) || w<350 || h<150 || w<=h*1.3) return given;
    CGFloat fittedH=floor(w/aspect());
    if (fittedH < 120 || fittedH>h || w>2500) return given;
    return CGRectMake(CGRectGetMinX(b),CGRectGetMidY(b)-fittedH/2.0,w,fittedH);
}
// Only override the identified game view, rather than globally resizing UIKit.
static void setGameFrame(id self,SEL cmd,CGRect proposed) {
    if(!oldFrame) return;
    UIView *v=(UIView *)self;
    if(!editingFrame && gameView && v==gameView && [NSThread isMainThread])
        proposed=fitRect(v,proposed);
    oldFrame(self,cmd,proposed);
}

static UIView *findHost(UIView *root,CALayer *layer,NSInteger depth) {
    if(!root || depth>22) return nil;
    if(root.layer==layer) return root;
    // Search children first to avoid matching UIWindow as layer ancestor.
    for(UIView *sub in root.subviews) {
        UIView *match=findHost(sub,layer,depth+1);
        if(match) return match;
    }
    CALayer *a=layer.superlayer;
    for(int j=0; a && j<6; ++j,a=a.superlayer)
        if(a==root.layer) return root;
    return nil;
}
static UIView *gameContainer(UIView *host) {
    // If Roblox wraps Metal in GameViewController, fit that whole hierarchy,
    // including game-owned UIKit overlays and hit testing.
    for(UIView *v=host;v;v=v.superview) {
        UIResponder *responder=v.nextResponder;
        if([responder isKindOfClass:[UIViewController class]] &&
           [NSStringFromClass([responder class]) containsString:@"GameViewController"]) return v;
    }
    return host;
}
static void fitMetalHost(CAMetalLayer *layer) {
    if(!layer || mode==0) return;
    if(![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ fitMetalHost(layer); }); return; }
    UIView *host=nil;
    id delegate=layer.delegate;
    if([delegate isKindOfClass:[UIView class]] && ((UIView *)delegate).layer==layer)
        host=(UIView *)delegate;
    if(!host) {
        for(UIWindow *window in UIApplication.sharedApplication.windows) {
            host=findHost(window,layer,0);
            if(host) break;
        }
    }
    if(!host || !host.superview || !host.window) {
        note(@"No active Metal UIView: skipped geometry fitting");
        return;
    }
    UIView *target=gameContainer(host);
    if(!target.superview || !target.window) return;
    CGRect before=target.frame, after=fitRect(target,before);
    if(CGRectEqualToRect(before,after)) return;
    gameView=target;
    target.superview.backgroundColor=UIColor.blackColor;
    target.clipsToBounds=YES;
    editingFrame=YES;
    target.frame=after;
    editingFrame=NO;
    [target setNeedsLayout];
    note(@"Fitted %@ %.1fx%.1f => %.1fx%.1f at y=%.1f delegate=%@",
         NSStringFromClass(target.class),before.size.width,before.size.height,
         after.size.width,after.size.height,after.origin.y,NSStringFromClass([delegate class]));
}

static void setMetalDrawable(id self,SEL cmd,CGSize requested) {
    CGSize result=requested;
    BOOL landscape=requested.width>requested.height*1.4 &&
        requested.width>400 && requested.height>150;
    if(mode && landscape) {
        int height=(int)llround(requested.width/aspect());
        height=(height+1)&~1;
        if(height>=150 && height<=8192) result.height=(double)height;
    }
    if(oldDrawable) oldDrawable(self,cmd,result);
    if(result.height<requested.height && result.width==requested.width) {
        CAMetalLayer *layer=(CAMetalLayer *)self;
        layer.contentsGravity=kCAGravityResizeAspect;
        layer.backgroundColor=UIColor.blackColor.CGColor;
        BOOL changed=lastLayer!=layer || !CGSizeEqualToSize(lastRequested,requested);
        if(changed) {
            lastLayer=layer; lastRequested=requested;
            note(@"Metal %.0fx%.0f => %.0fx%.0f",requested.width,requested.height,result.width,result.height);
            dispatch_async(dispatch_get_main_queue(), ^{ fitMetalHost(layer); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.35*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{fitMetalHost(layer);});
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.0*NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{fitMetalHost(layer);});
        }
    }
}
__attribute__((constructor)) static void startProbe(void) {
    @autoreleasepool {
        id p=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"DeltaAspectMode"];
        mode=[p respondsToSelector:@selector(integerValue)] ? [p integerValue] : 0;
        if(mode<0 || mode>2) mode=0;
        Method drawable=class_getInstanceMethod(CAMetalLayer.class,@selector(setDrawableSize:));
        if(drawable) oldDrawable=(void(*)(id,SEL,CGSize))method_setImplementation(drawable,(IMP)setMetalDrawable);
        Method frame=class_getInstanceMethod(UIView.class,@selector(setFrame:));
        if(frame) oldFrame=(void(*)(id,SEL,CGRect))method_setImplementation(frame,(IMP)setGameFrame);
        note(@"Start mode=%ld metalHook=%d frameHook=%d",(long)mode,oldDrawable!=NULL,oldFrame!=NULL);
    }
}
