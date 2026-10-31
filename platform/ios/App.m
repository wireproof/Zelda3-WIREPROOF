#import <UIKit/UIKit.h>
#import <TargetConditionals.h>
#import <QuartzCore/QuartzCore.h>
#import <GameController/GameController.h>
#import <AVFoundation/AVFoundation.h>
#import "Audio.h"
#include "../native/zelda_native.h"

@interface ZButton : UIButton
@property(nonatomic) uint16_t mask;
@property(nonatomic) BOOL down;
@end
@implementation ZButton
- (BOOL)beginTracking:(UITouch*)t withEvent:(UIEvent*)e {self.down=YES;self.alpha=.55;return YES;}
- (BOOL)continueTracking:(UITouch*)t withEvent:(UIEvent*)e {return YES;}
- (void)endTracking:(UITouch*)t withEvent:(UIEvent*)e {self.down=NO;self.alpha=1;}
- (void)cancelTrackingWithEvent:(UIEvent*)e {self.down=NO;self.alpha=1;}
@end
@interface ZPad : UIView
@property(nonatomic) uint16_t mask;
@end
@implementation ZPad
- (instancetype)init {if((self=[super init])) {self.backgroundColor=UIColor.clearColor;self.accessibilityLabel=@"Directional pad";self.isAccessibilityElement=YES;}return self;}
- (void)drawRect:(CGRect)rect {
  CGFloat s=self.bounds.size.width,c=s/3;
  [[UIColor colorWithRed:.16 green:.20 blue:.19 alpha:1] setFill];
  UIBezierPath *p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(c,2,c,s-4) cornerRadius:12];[p fill];
  p=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,c,s-4,c) cornerRadius:12];[p fill];
  NSDictionary *attrs=@{NSFontAttributeName:[UIFont systemFontOfSize:24 weight:UIFontWeightMedium],NSForegroundColorAttributeName:[UIColor colorWithWhite:.8 alpha:1]};
  NSArray *labels=@[@"▲",@"▼",@"◀",@"▶"];
  CGPoint points[4]={{s/2,c/2},{s/2,s-c/2},{c/2,s/2},{s-c/2,s/2}};
  for(int i=0;i<4;i++){CGSize z=[labels[i] sizeWithAttributes:attrs];[labels[i] drawAtPoint:CGPointMake(points[i].x-z.width/2,points[i].y-z.height/2) withAttributes:attrs];}
}
- (void)update:(NSSet<UITouch*>*)touches {
  CGPoint p=[touches.anyObject locationInView:self];CGFloat c=self.bounds.size.width/2;
  CGFloat x=(p.x-c)/c,y=(p.y-c)/c;uint16_t m=0;
  if(x<-.26)m|=64;if(x>.26)m|=128;if(y<-.26)m|=16;if(y>.26)m|=32;
  self.mask=m;
}
- (void)touchesBegan:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {[self update:t];}
- (void)touchesMoved:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {[self update:t];}
- (void)touchesEnded:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {self.mask=0;}
- (void)touchesCancelled:(NSSet<UITouch*>*)t withEvent:(UIEvent*)e {self.mask=0;}
@end

@interface GameController : UIViewController {
  uint32_t _pixels[256*240];
  int16_t _pcm[534*2];
  unsigned _sampleRemainder,_frames;
  CFTimeInterval _last,_elapsed;
  BOOL _ready,_menuOpen,_interrupted,_qaMode;
}
@property(nonatomic,strong) UIView *screen;
@property(nonatomic,strong) ZPad *pad;
@property(nonatomic,strong) NSMutableArray<ZButton*> *buttons;
@property(nonatomic,strong) UIButton *menu;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) CADisplayLink *display;
@property(nonatomic,strong) ZAudio *audio;
- (void)suspend;
- (void)resume;
@end
@implementation GameController
- (BOOL)prefersStatusBarHidden {return YES;}
- (BOOL)prefersHomeIndicatorAutoHidden {return YES;}
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {return UIRectEdgeAll;}
- (void)viewDidLoad {
  [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
  self.view.backgroundColor=[UIColor colorWithRed:.035 green:.055 blue:.05 alpha:1];
  self.view.multipleTouchEnabled=YES;
  self.screen=[UIView new];self.screen.backgroundColor=UIColor.blackColor;
  self.screen.layer.magnificationFilter=kCAFilterNearest;self.screen.layer.minificationFilter=kCAFilterNearest;
  self.screen.isAccessibilityElement=YES;self.screen.accessibilityLabel=@"A Link to the Past game screen";
  [self.view addSubview:self.screen];self.pad=[ZPad new];[self.view addSubview:self.pad];
  self.buttons=[NSMutableArray array];
  NSArray *names=@[@"B",@"Y",@"A",@"X",@"L",@"R",@"SELECT",@"START"];
  uint16_t masks[]={1,2,256,512,1024,2048,4,8};
  for(int i=0;i<8;i++) {
    ZButton *b=[ZButton buttonWithType:UIButtonTypeCustom];b.mask=masks[i];
    [b setTitle:names[i] forState:UIControlStateNormal];b.accessibilityLabel=names[i];
    b.titleLabel.font=[UIFont systemFontOfSize:i<4?22:13 weight:UIFontWeightBold];
    b.backgroundColor=i==0?[UIColor colorWithRed:.43 green:.32 blue:.13 alpha:1]:[UIColor colorWithRed:.15 green:.20 blue:.18 alpha:1];
    b.layer.borderWidth=1;b.layer.borderColor=[UIColor colorWithWhite:1 alpha:.12].CGColor;
    [self.view addSubview:b];[self.buttons addObject:b];
  }
  self.menu=[UIButton buttonWithType:UIButtonTypeSystem];[self.menu setTitle:@"PAUSE" forState:UIControlStateNormal];self.menu.tintColor=[UIColor colorWithRed:.85 green:.76 blue:.49 alpha:1];self.menu.accessibilityLabel=@"Pause menu";
  [self.menu addTarget:self action:@selector(showMenu) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:self.menu];
  self.titleLabel=[UILabel new];self.titleLabel.text=@"A LINK TO THE PAST";self.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];self.titleLabel.textColor=[UIColor colorWithWhite:.65 alpha:1];[self.view addSubview:self.titleLabel];
  NSFileManager *fm=NSFileManager.defaultManager;
  NSURL *dir=[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  BOOL smoke=NO;
#if TARGET_OS_SIMULATOR
  smoke=[NSProcessInfo.processInfo.arguments containsObject:@"--smoke"];
  _qaMode=smoke || [NSProcessInfo.processInfo.arguments containsObject:@"--smoke-restore"];
  if(_qaMode) dir=[dir URLByAppendingPathComponent:@"QA" isDirectory:YES];
#endif
  NSError *error=nil;
  if(![fm createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:&error]) {self.titleLabel.text=@"Cannot open save directory";return;}
  NSString *asset=[NSBundle.mainBundle pathForResource:@"zelda3_assets" ofType:@"dat"];
  _ready=asset && WP_Init(asset.fileSystemRepresentation,dir.fileSystemRepresentation);
  if(!_ready) {self.titleLabel.text=@"Game assets could not be loaded";return;}
#if TARGET_OS_SIMULATOR
  if(smoke) {[self runSmoke];}
#endif
  BOOL restored=WP_Load("saves/autosave.sav");NSLog(@"ZELDA_NATIVE_READY restored=%d",restored);
#if TARGET_OS_SIMULATOR
  if(_qaMode) {
    NSDictionary *receipt=@{@"restored":@(restored),@"state_hash":@(WP_StateHash())};
    [[NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingPrettyPrinted error:nil] writeToFile:@"launch.json" atomically:YES];
  }
#endif
  self.audio=[ZAudio new];self.display=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
  self.display.preferredFramesPerSecond=60;[self.display addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interruption:) name:AVAudioSessionInterruptionNotification object:nil];
  [self resume];
}

#if TARGET_OS_SIMULATOR
- (void)runSmoke {
  NSFileManager *fm=NSFileManager.defaultManager;
  NSString *refs=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"ref"];
  if(![fm fileExistsAtPath:@"saves/ref"]) [fm copyItemAtPath:refs toPath:@"saves/ref" error:nil];
  NSMutableArray *checks=[NSMutableArray array];
  BOOL all=YES;
  for(int chapter=0;chapter<=13;chapter++) {
    if(chapter)WP_LoadReference(chapter);
    unsigned nonzero=0;int frames=chapter?300:1200;
    for(int j=0;j<frames;j++) {
      WP_Step(0,_pixels,_pcm,534);
      for(int k=0;k<1068;k++)nonzero+=_pcm[k]!=0;
    }
    BOOL visual=NO;for(int k=1;k<256*224;k++)if(_pixels[k]!=_pixels[0]){visual=YES;break;}
    all &= visual && nonzero>0;
    [checks addObject:@{@"chapter":@(chapter),@"frames":@(frames),@"audio_nonzero_samples":@(nonzero),@"nonblank_frame":@(visual)}];
    [self render];
    CGImageRef image=(__bridge CGImageRef)self.screen.layer.contents;
    [UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:[NSString stringWithFormat:@"chapter-%02d.png",chapter] atomically:YES];
  }
  WP_LoadReference(4);
  BOOL saved=WP_Save("saves/qa-checkpoint.sav");
  for(int j=0;j<60;j++) WP_Step(16,_pixels,_pcm,534);
  uint32_t first=WP_StateHash();
  BOOL loaded=WP_Load("saves/qa-checkpoint.sav");
  for(int j=0;j<60;j++) WP_Step(16,_pixels,_pcm,534);
  uint32_t second=WP_StateHash();
  [@"broken" writeToFile:@"saves/qa-invalid.sav" atomically:YES encoding:NSUTF8StringEncoding error:nil];
  BOOL rejected=!WP_Load("saves/qa-invalid.sav");
  all &= saved && loaded && first==second && rejected;
  NSDictionary *result=@{@"pass":@(all),@"chapters":checks,@"checkpoint_saved":@(saved),@"checkpoint_loaded":@(loaded),@"replay_hash_first":@(first),@"replay_hash_second":@(second),@"invalid_save_rejected":@(rejected)};
  [[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil] writeToFile:@"smoke.json" atomically:YES];
  NSLog(@"ZELDA_IOS_SMOKE %@",result);
  WP_Reset();for(int j=0;j<1200;j++)WP_Step(0,_pixels,_pcm,534);
}
#endif


#if TARGET_OS_SIMULATOR
- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  if(!_qaMode)return;
  [self.view layoutIfNeeded];
  // Unit-level multi-button state check, independent of physical multitouch testing.
  [self.buttons[0] beginTracking:nil withEvent:nil];self.pad.mask=64;
  BOOL simultaneous=([self input] & 65)==65;
  [self.buttons[0] cancelTrackingWithEvent:nil];self.pad.mask=0;
  BOOL cleared=([self input]&65)==0;
  NSDictionary *layout=@{@"bounds":NSStringFromCGRect(self.view.bounds),@"safeArea":NSStringFromUIEdgeInsets(self.view.safeAreaInsets),@"game":NSStringFromCGRect(self.screen.frame),@"dpad":NSStringFromCGRect(self.pad.frame),@"simultaneous_input":@(simultaneous),@"released_input":@(cleared)};
  [[NSJSONSerialization dataWithJSONObject:layout options:NSJSONWritingPrettyPrinted error:nil] writeToFile:@"layout.json" atomically:YES];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithBounds:self.view.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *c){[self.view.layer renderInContext:c.CGContext];}];
    [UIImagePNGRepresentation(image) writeToFile:@"layout.png" atomically:YES];
    CGRect original=self.view.bounds;
    CGFloat width=MAX(original.size.width,original.size.height),height=MIN(original.size.width,original.size.height);
    self.view.bounds=CGRectMake(0,0,width,height);
    CGFloat side=height<500?62:0;
    [self layoutControlsInRect:CGRectMake(side,0,width-2*side,height-25)];
    UIGraphicsImageRenderer *wide=[[UIGraphicsImageRenderer alloc]initWithBounds:self.view.bounds];
    UIImage *landscape=[wide imageWithActions:^(UIGraphicsImageRendererContext *c){[self.view.layer renderInContext:c.CGContext];}];
    [UIImagePNGRepresentation(landscape) writeToFile:@"layout-landscape.png" atomically:YES];
    BOOL clear=!CGRectIntersectsRect(self.screen.frame,self.pad.frame);
    for(ZButton *b in self.buttons)clear &= !CGRectIntersectsRect(self.screen.frame,b.frame);
    NSDictionary *wideResult=@{@"synthetic_layout":@YES,@"game_clear_of_controls":@(clear),@"game":NSStringFromCGRect(self.screen.frame)};
    [[NSJSONSerialization dataWithJSONObject:wideResult options:NSJSONWritingPrettyPrinted error:nil] writeToFile:@"landscape.json" atomically:YES];
    self.view.bounds=original;[self viewDidLayoutSubviews];

  });
}
#endif

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];UIEdgeInsets insets=self.view.safeAreaInsets;
  [self layoutControlsInRect:UIEdgeInsetsInsetRect(self.view.bounds,insets)];
}
- (void)layoutControlsInRect:(CGRect)r {
  CGFloat w=r.size.width,h=r.size.height,x=r.origin.x,y=r.origin.y;
  BOOL landscape=w>h;
  self.titleLabel.frame=CGRectMake(x+18,y+4,w-110,32);self.menu.frame=CGRectMake(x+w-88,y,76,40);
  CGFloat pad=MIN(176,landscape?MIN(h-110,w*.21):w*.42);
  CGFloat bottom=y+h-12;
  CGFloat controlY=landscape?y+MAX(64,(h-pad)/2):bottom-pad-42;
  CGFloat left=x+16,right=x+w-16-pad;
  self.pad.frame=CGRectMake(left,controlY,pad,pad);[self.pad setNeedsDisplay];
  CGFloat d=pad*.34,offset=(pad-d)/2;
  CGPoint coords[4]={{offset,pad-d},{0,offset},{pad-d,offset},{offset,0}};
  for(int i=0;i<4;i++){self.buttons[i].frame=CGRectMake(right+coords[i].x,controlY+coords[i].y,d,d);self.buttons[i].layer.cornerRadius=d/2;}
  self.buttons[4].frame=CGRectMake(left,controlY-48,pad,40);self.buttons[5].frame=CGRectMake(right,controlY-48,pad,40);
  CGFloat middle=x+w/2;
  self.buttons[6].frame=CGRectMake(middle-86,bottom-38,78,38);self.buttons[7].frame=CGRectMake(middle+8,bottom-38,78,38);
  for(int i=4;i<8;i++) self.buttons[i].layer.cornerRadius=12;
  CGRect area=landscape?CGRectMake(x+pad+34,y+42,w-2*pad-68,h-102):CGRectMake(x+16,y+42,w-32,controlY-y-100);
  CGFloat scale=MIN(area.size.width/256,area.size.height/224);scale=MAX(.1,scale);
  CGSize size=CGSizeMake(floor(256*scale),floor(224*scale));
  self.screen.frame=CGRectMake(CGRectGetMidX(area)-size.width/2,CGRectGetMidY(area)-size.height/2,size.width,size.height);
}
- (uint16_t)input {
  uint16_t m=self.pad.mask;
  for(ZButton *b in self.buttons)if(b.down)m|=b.mask;
  for(GCController *c in GCController.controllers) {
    GCExtendedGamepad *g=c.extendedGamepad;if(!g)continue;
    if(g.dpad.up.isPressed || g.leftThumbstick.yAxis.value>.35)m|=16;
    if(g.dpad.down.isPressed || g.leftThumbstick.yAxis.value<-.35)m|=32;
    if(g.dpad.left.isPressed || g.leftThumbstick.xAxis.value<-.35)m|=64;
    if(g.dpad.right.isPressed || g.leftThumbstick.xAxis.value>.35)m|=128;
    /* Physical positions match the SNES: south=B, east=A, west=Y, north=X. */
    if(g.buttonA.isPressed)m|=1;if(g.buttonB.isPressed)m|=256;
    if(g.buttonX.isPressed)m|=2;if(g.buttonY.isPressed)m|=512;
    if(g.leftShoulder.isPressed)m|=1024;if(g.rightShoulder.isPressed)m|=2048;
    if(g.buttonMenu.isPressed)m|=8;if(g.buttonOptions.isPressed)m|=4;
  }
  return m;
}
- (void)render {
  CFDataRef data=CFDataCreate(NULL,(uint8_t*)_pixels,256*224*4);
  CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);
  CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
  CGImageRef image=CGImageCreate(256,224,8,32,1024,space,kCGBitmapByteOrder32Little|kCGImageAlphaNoneSkipFirst,provider,NULL,false,kCGRenderingIntentDefault);
  [CATransaction begin];[CATransaction setDisableActions:YES];self.screen.layer.contents=(__bridge id)image;[CATransaction commit];
  CGImageRelease(image);CGColorSpaceRelease(space);CGDataProviderRelease(provider);CFRelease(data);
}
- (void)tick:(CADisplayLink*)link {
  if(!_ready || _menuOpen || _interrupted)return;
  if(!_last)_last=link.timestamp-1.0/60;
  _elapsed+=MIN(link.timestamp-_last,.1);_last=link.timestamp;
  int count=0;
  while(_elapsed>=1.0/60 && count++<4) {
    _sampleRemainder+=32000;int samples=_sampleRemainder/60;_sampleRemainder%=60;
    WP_Step([self input],_pixels,_pcm,samples);[self.audio push:_pcm frames:samples];
    _elapsed-=1.0/60;_frames++;
    if(_frames%1800==0 && !WP_Save("saves/autosave.sav"))NSLog(@"Autosave failed");
  }
  if(count)[self render];
}
- (void)clearInput {self.pad.mask=0;for(ZButton *b in self.buttons){b.down=NO;b.alpha=1;}}
- (void)suspend {
  if(!_ready)return;
  self.display.paused=YES;[self.audio stop];[self clearInput];_last=_elapsed=0;
  BOOL ok=WP_Save("saves/autosave.sav");NSLog(@"ZELDA_AUTOSAVE %d",ok);
}
- (void)resume {
  if(!_ready || _menuOpen || _interrupted)return;
  _last=_elapsed=0;self.display.paused=NO;
  if(![self.audio start])NSLog(@"Audio output unavailable; game continues");
}
- (void)interruption:(NSNotification*)n {
  _interrupted=[n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue]==AVAudioSessionInterruptionTypeBegan;
  if(_interrupted)[self suspend];else if(UIApplication.sharedApplication.applicationState==UIApplicationStateActive)[self resume];
}
- (void)presentDialog:(UIAlertController*)dialog {
  if(self.presentedViewController) [self dismissViewControllerAnimated:YES completion:^{[self presentViewController:dialog animated:YES completion:nil];}];
  else [self presentViewController:dialog animated:YES completion:nil];
}
- (void)message:(NSString*)title detail:(NSString*)detail {
  UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){self->_menuOpen=NO;[self resume];}]];[self presentDialog:a];
}
- (void)showMenu {
  if(!_ready || _menuOpen)return;_menuOpen=YES;[self suspend];
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"A Link to the Past" message:@"Your progress is saved automatically. Manual checkpoints are kept separately." preferredStyle:UIAlertControllerStyleActionSheet];
  [a addAction:[UIAlertAction actionWithTitle:@"Resume" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){self->_menuOpen=NO;[self resume];}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Save checkpoint" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){BOOL ok=WP_Save("saves/checkpoint.sav");[self message:ok?@"Checkpoint saved":@"Save failed" detail:ok?@"You can return here from the pause menu.":@"Your previous checkpoint has been preserved."];}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Load checkpoint…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self confirmLoad];}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Controls" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self message:@"Controls" detail:@"B: sword • A: action\nY: equipped item • X: map\nSTART: inventory • SELECT: save menu\n\nControllers use SNES button positions.\nRotate your device for landscape controls."];}]];
  a.popoverPresentationController.sourceView=self.menu;a.popoverPresentationController.sourceRect=self.menu.bounds;
  [self presentDialog:a];
}
- (void)confirmLoad {
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Load checkpoint?" message:@"Play will return to your manual checkpoint. Your current position was autosaved." preferredStyle:UIAlertControllerStyleAlert];
  [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){self->_menuOpen=NO;[self resume];}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Load" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){BOOL ok=WP_Load("saves/checkpoint.sav");if(!ok)[self message:@"No valid checkpoint" detail:@"Save a checkpoint first. Your current game has not been changed."];else {self->_menuOpen=NO;[self resume];}}]];
  [self presentDialog:a];
}
@end
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) GameController *game;
@end
@implementation SceneDelegate
- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options {
  if(![scene isKindOfClass:UIWindowScene.class])return;
  self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene*)scene];
  self.game=[GameController new];self.window.rootViewController=self.game;
  [self.window makeKeyAndVisible];
}
- (void)sceneWillResignActive:(UIScene*)scene {[self.game suspend];}
- (void)sceneDidBecomeActive:(UIScene*)scene {[self.game resume];}
- (void)sceneDidEnterBackground:(UIScene*)scene {[self.game suspend];}
- (void)sceneDidDisconnect:(UIScene*)scene {[self.game suspend];}
@end
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication*)a didFinishLaunchingWithOptions:(NSDictionary*)options {return YES;}
@end
int main(int argc,char **argv) {@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
