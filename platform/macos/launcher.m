#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <unistd.h>

static void Fail(NSString *message) {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Zelda3 could not start";
  alert.informativeText = message;
  [alert runModal];
  exit(1);
}
int main(void) {
  @autoreleasepool {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSBundle *bundle = NSBundle.mainBundle;
    NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory
                               inDomains:NSUserDomainMask].firstObject;
    NSURL *data = [support URLByAppendingPathComponent:@"WIREPROOF/Zelda3" isDirectory:YES];
    NSError *error = nil;
    if (![fm createDirectoryAtURL:data withIntermediateDirectories:YES attributes:nil error:&error])
      Fail(error.localizedDescription);
    for (NSString *name in @[@"zelda3_assets.dat", @"zelda3.ini"]) {
      NSURL *destination = [data URLByAppendingPathComponent:name];
      if (![fm fileExistsAtPath:destination.path]) {
        NSURL *source = [bundle.resourceURL URLByAppendingPathComponent:name];
        if (![fm copyItemAtURL:source toURL:destination error:&error]) Fail(error.localizedDescription);
      }
    }
    if (chdir(data.fileSystemRepresentation)) Fail(@"Cannot open game data directory.");
    NSString *engine = [bundle.executablePath.stringByDeletingLastPathComponent
                        stringByAppendingPathComponent:@"zelda3-engine"];
    execl(engine.fileSystemRepresentation, "zelda3-engine", "--config", "zelda3.ini", NULL);
    Fail(@"Cannot launch game engine.");
  }
}
