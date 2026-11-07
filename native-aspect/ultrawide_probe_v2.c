// V2 experimental aspect-fit probe: non-stretched Metal output, NOT camera FOV.
// Explicit mode in Info.plist: 0=observe, 1=21:9, 2=32:9.
// Do not install without separate test/signing. No network access or telemetry.
typedef void* id;
typedef void* SEL;
typedef void* Method;
typedef struct { double width, height; } CGSize;
extern id objc_getClass(const char*);
extern SEL sel_registerName(const char*);
extern Method class_getInstanceMethod(id, SEL);
extern void* method_setImplementation(Method, void*);
extern void* objc_msgSend(void*,void*,...);
extern void NSLog(id,...);
extern char* getenv(const char*);
extern int open(const char*,int,...);
extern long write(int,const void*,unsigned long);
extern int close(int);
extern int snprintf(char*,unsigned long,const char*,...);
static void (*original_set_drawable)(id,SEL,CGSize)=0;
static int mode=0;
static int logs=0;
static CGSize last={0,0};
static id ns(const char *s) {
  return ((id(*)(id,SEL,const char*))objc_msgSend)(objc_getClass("NSString"),sel_registerName("stringWithUTF8String:"),s);
}
static void logsize(CGSize before,CGSize after) {
  if (++logs>80) return;
  char *home=getenv("HOME"); char path[1024],line[256];
  if (home) {
    int n=snprintf(path,sizeof(path),"%s/Documents/DeltaAspectV2.log",home);
    if(n>0 && n<(int)sizeof(path)) {
      n=snprintf(line,sizeof(line),"drawable in=%.0fx%.0f out=%.0fx%.0f mode=%d\n",before.width,before.height,after.width,after.height,mode);
      if(n>0 && n<(int)sizeof(line)) {
        int fd=open(path,0x1|0x200|0x8,0644);
        if(fd>=0) { write(fd,line,(unsigned long)n);close(fd); }
      }
    }
  }
  NSLog(ns("[DeltaAspectV2] drawable in=%.0fx%.0f out=%.0fx%.0f mode=%d"),before.width,before.height,after.width,after.height,mode);
}
static void set_drawable(id self,SEL sel,CGSize requested) {
  CGSize result=requested;
  if(mode && requested.width>400 && requested.height>150 && requested.width>requested.height*1.4) {
    double aspect=mode==2 ? 32.0/9.0 : 21.0/9.0;
    int h=(int)(requested.width/aspect+0.5);
    h=(h+1)&~1;
    if(h>=150 && h<=8192) result.height=(double)h;
  }
  if(requested.width!=last.width || requested.height!=last.height) {
    logsize(requested,result); last=requested;
  }
  if(original_set_drawable) original_set_drawable(self,sel,result);
  // V2: Core Animation defaults to "resize" and was visibly stretching
  // the 32:9 drawable to the physical phone layer. Use aspect-preserving
  // compositing. Keeps UIKit view geometry and touches untouched.
  if (result.height < requested.height && result.width == requested.width) {
    ((void(*)(id,SEL,id))objc_msgSend)(
      self,sel_registerName("setContentsGravity:"),ns("resizeAspect"));
    id colorClass=objc_getClass("UIColor");
    if (colorClass) {
      id black=((id(*)(id,SEL))objc_msgSend)(
        colorClass,sel_registerName("blackColor"));
      if (black) {
        id cg=((id(*)(id,SEL))objc_msgSend)(
          black,sel_registerName("CGColor"));
        if (cg) ((void(*)(id,SEL,id))objc_msgSend)(
          self,sel_registerName("setBackgroundColor:"),cg);
      }
    }
  }
}
__attribute__((constructor))
static void aspect_init(void) {
  id bundle=((id(*)(id,SEL))objc_msgSend)(objc_getClass("NSBundle"),sel_registerName("mainBundle"));
  id dict=bundle?((id(*)(id,SEL))objc_msgSend)(bundle,sel_registerName("infoDictionary")):0;
  id value=dict?((id(*)(id,SEL,id))objc_msgSend)(dict,sel_registerName("objectForKey:"),ns("DeltaAspectMode")):0;
  if(value) mode=((int(*)(id,SEL))objc_msgSend)(value,sel_registerName("intValue"));
  if(mode<0 || mode>2) mode=0;
  id cls=objc_getClass("CAMetalLayer");
  Method method=cls?class_getInstanceMethod(cls,sel_registerName("setDrawableSize:")):0;
  if(method) original_set_drawable=(void(*)(id,SEL,CGSize))method_setImplementation(method,(void*)set_drawable);
  NSLog(ns("[DeltaAspectV2] initialized; mode=%d hook=%d"),mode,original_set_drawable!=0);
}
