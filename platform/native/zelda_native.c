#include "zelda_native.h"
#include "src/zelda_rtl.h"
#include "src/assets.h"
#include "src/config.h"
#include "src/util.h"
#include "src/audio.h"
#include "snes/ppu.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>

Config g_config;
const uint8 *g_asset_ptrs[kNumberOfAssets];
uint32 g_asset_sizes[kNumberOfAssets];
static uint8 *asset_data;
static uint32 Read32(const uint8 *p) {
  return (uint32)p[0] | (uint32)p[1]<<8 | (uint32)p[2]<<16 | (uint32)p[3]<<24;
}
void Die(const char *error) { fprintf(stderr, "Zelda3: %s\n", error); abort(); }
/* All engine calls and PCM synthesis happen on the app's main thread. */
void ZeldaApuLock(void) {}
void ZeldaApuUnlock(void) {}
MemBlk FindInAssetArray(int asset, int idx) {
  return FindIndexInMemblk((MemBlk){g_asset_ptrs[asset], g_asset_sizes[asset]}, idx);
}
bool WP_Init(const char *assets, const char *data_directory) {
  if (asset_data) return false;
  size_t length=0;
  uint8 *data=ReadWholeFile(assets,&length);
  static const char sig[]={kAssets_Sig};
  if (!data) return false;
  if (length < 88+kNumberOfAssets*4 || memcmp(data,sig,48) || Read32(data+80)!=kNumberOfAssets) { free(data); return false; }
  uint64 offset=88+kNumberOfAssets*4+(uint64)Read32(data+84);
  for (int i=0;i<kNumberOfAssets;i++) {
    offset=(offset+3)&~(uint64)3;
    uint32 size=Read32(data+88+i*4);
    if (offset+size>length) {free(data);return false;}
    g_asset_ptrs[i]=data+offset;g_asset_sizes[i]=size;offset+=size;
  }
  if (chdir(data_directory)) {free(data);return false;}
  mkdir("saves",0755);
  asset_data=data;
  g_config.audio_freq=32000;g_config.audio_channels=2;g_config.enable_audio=true;
  ZeldaInitialize();g_zenv.ppu->extraLeftRight=0;
  ZeldaEnableMsu(0);ZeldaSetLanguage("us");ZeldaReadSram();
  return true;
}
void WP_Step(uint16_t buttons,uint32_t *pixels,int16_t *audio,int samples) {
  ZeldaRunFrame(buttons);
  ZeldaDrawPpuFrame((uint8*)pixels,256*4,kPpuRenderFlags_NewRenderer);
  ZeldaRenderAudio(audio,samples,2);
}
bool WP_Save(const char *path) {return ZeldaSaveStatePath(path);}
bool WP_Load(const char *path) {return ZeldaLoadStatePath(path);}
void WP_Reset(void) {ZeldaReset(true);g_zenv.ppu->extraLeftRight=0;}
void WP_LoadReference(int chapter) {SaveLoadSlot(kSaveLoad_Load,256+chapter-1);g_zenv.ppu->extraLeftRight=0;}
uint32_t WP_StateHash(void) {
  uint32_t h=2166136261u;
  for(int i=0;i<131072;i++) h=(h^g_zenv.ram[i])*16777619u;
  return h;
}
