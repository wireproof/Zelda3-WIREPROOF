#pragma once
#include <stdbool.h>
#include <stdint.h>
/* Single-threaded API. Audio playback callbacks must only consume copied PCM. */
bool WP_Init(const char *assets, const char *data_directory);
void WP_Step(uint16_t buttons, uint32_t *pixels, int16_t *audio, int samples);
bool WP_Save(const char *path);
bool WP_Load(const char *path);
void WP_Reset(void);
void WP_LoadReference(int chapter);
uint32_t WP_StateHash(void);
