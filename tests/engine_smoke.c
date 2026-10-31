/* Reuse the production asset loader and runtime for bounded desktop checks.
 * Run only in a disposable directory: the engine can write SRAM there. */
#include <SDL.h>
#define ZELDA_ENTRY_POINT zelda_desktop_main
#include "../src/main.c"
#undef main

int main(int argc, char **argv) {
  if (argc != 4) {
    fprintf(stderr, "usage: zelda3_smoke chapter(0=boot,1..13) frames output.bmp\n");
    return 2;
  }
  int chapter = atoi(argv[1]), frames = atoi(argv[2]);
  if (chapter < 0 || chapter > 13 || frames < 1 || frames > 1000000) return 2;
  if (SDL_Init(SDL_INIT_TIMER)) return 3;
  ParseConfigFile("zelda3.ini");
  LoadAssets();
  ZeldaInitialize();
  g_zenv.ppu->extraLeftRight = 0;
  ZeldaSetLanguage("us");
  g_audio_mutex = SDL_CreateMutex();
  if (!g_audio_mutex) return 3;
  if (chapter) SaveLoadSlot(kSaveLoad_Load, 256 + chapter - 1);
  uint32 *pixels = calloc(256 * 240, 4);
  int16 audio[534 * 2];
  uint64 audio_nonzero = 0;
  if (!pixels) return 4;
  for (int i = 0; i < frames; ++i) {
    ZeldaRunFrame(0);
    ZeldaDrawPpuFrame((uint8 *)pixels, 256 * 4, kPpuRenderFlags_NewRenderer);
    ZeldaRenderAudio(audio, 534, 2);
    for (size_t j = 0; j < 534 * 2; ++j) audio_nonzero += audio[j] != 0;
  }
  SDL_Surface *surface = SDL_CreateRGBSurfaceFrom(pixels, 256, 224, 32, 1024,
      0x00ff0000, 0x0000ff00, 0x000000ff, 0);
  if (!surface || SDL_SaveBMP(surface, argv[3])) return 5;
  printf("chapter=%d frames=%d nonzero_audio_samples=%llu\n", chapter, frames,
         (unsigned long long)audio_nonzero);
  SDL_FreeSurface(surface);
  free(pixels);
  SDL_DestroyMutex(g_audio_mutex);
  SDL_Quit();
  return 0;
}
