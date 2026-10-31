#import <Foundation/Foundation.h>
@interface ZAudio : NSObject
- (BOOL)start;
- (void)stop;
- (void)push:(const int16_t *)samples frames:(unsigned)frames;
@end
