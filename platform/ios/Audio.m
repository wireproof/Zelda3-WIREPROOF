#import "Audio.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <os/lock.h>
@interface ZAudio () {
  AudioQueueRef _queue;
  int16_t _ring[16384*2];
  unsigned _read,_write;
  os_unfair_lock _lock;
}
- (void)fill:(AudioQueueBufferRef)buffer queue:(AudioQueueRef)queue;
@end
static void Callback(void *ctx,AudioQueueRef q,AudioQueueBufferRef b) { [(__bridge ZAudio*)ctx fill:b queue:q]; }
@implementation ZAudio
- (instancetype)init { if((self=[super init])) _lock=OS_UNFAIR_LOCK_INIT;return self; }
- (void)fill:(AudioQueueBufferRef)b queue:(AudioQueueRef)q {
  int16_t *out=b->mAudioData;
  os_unfair_lock_lock(&_lock);
  for(unsigned i=0;i<512;i++) {
    if(_read!=_write) {out[i*2]=_ring[(_read%16384)*2];out[i*2+1]=_ring[(_read%16384)*2+1];_read++;}
    else {out[i*2]=out[i*2+1]=0;}
  }
  os_unfair_lock_unlock(&_lock);
  b->mAudioDataByteSize=512*4;AudioQueueEnqueueBuffer(q,b,0,NULL);
}
- (BOOL)start {
  if(_queue) return YES;
  NSError *error=nil;
  AVAudioSession *session=AVAudioSession.sharedInstance;
  if(![session setCategory:AVAudioSessionCategoryPlayback error:&error] || ![session setActive:YES error:&error]) {NSLog(@"Audio session: %@",error);return NO;}
  AudioStreamBasicDescription f={0};f.mSampleRate=32000;f.mFormatID=kAudioFormatLinearPCM;
  f.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
  f.mBytesPerPacket=4;f.mFramesPerPacket=1;f.mBytesPerFrame=4;f.mChannelsPerFrame=2;f.mBitsPerChannel=16;
  _read=_write=0;
  if(AudioQueueNewOutput(&f,Callback,(__bridge void*)self,NULL,NULL,0,&_queue)) {_queue=NULL;return NO;}
  for(int i=0;i<3;i++) {
    AudioQueueBufferRef b=NULL;
    if(AudioQueueAllocateBuffer(_queue,512*4,&b)) {[self stop];return NO;}
    [self fill:b queue:_queue];
  }
  if(AudioQueueStart(_queue,NULL)) {[self stop];return NO;}
  return YES;
}
- (void)stop {
  if(_queue) {AudioQueueStop(_queue,true);AudioQueueDispose(_queue,true);_queue=NULL;}
  os_unfair_lock_lock(&_lock);_read=_write=0;os_unfair_lock_unlock(&_lock);
}
- (void)push:(const int16_t*)samples frames:(unsigned)n {
  os_unfair_lock_lock(&_lock);
  for(unsigned i=0;i<n;i++) {
    if(_write-_read>=4096) _read=_write-2048;
    _ring[(_write%16384)*2]=samples[i*2];_ring[(_write%16384)*2+1]=samples[i*2+1];_write++;
  }
  os_unfair_lock_unlock(&_lock);
}
- (void)dealloc {[self stop];}
@end
