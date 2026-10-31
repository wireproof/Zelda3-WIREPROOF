from pathlib import Path
import subprocess,concurrent.futures,json,shutil
p=Path(__file__).resolve().parents[1];out=p/'build/palmos-probe';out.mkdir(parents=True,exist_ok=True);inc=out/'include';inc.mkdir(exist_ok=True)
source=out/'source'
for directory in ['src','snes','third_party']:
 shutil.copytree(p/directory,source/directory,dirs_exist_ok=True)
p=source
f=p/'src/dungeon.h';t=f.read_text().replace('typedef struct RoomBounds RoomBounds;','#ifndef WP_ROOM_BOUNDS_TYPE\n#define WP_ROOM_BOUNDS_TYPE\ntypedef struct RoomBounds RoomBounds;\n#endif');f.write_text(t)
f=p/'src/variables.h';t=f.read_text().replace('typedef struct RoomBounds {','struct RoomBounds {').replace('} RoomBounds;','};\n#ifndef WP_ROOM_BOUNDS_TYPE\n#define WP_ROOM_BOUNDS_TYPE\ntypedef struct RoomBounds RoomBounds;\n#endif');f.write_text(t)
headers={
'stdint.h':'''#ifndef WP_STDINT_H
#define WP_STDINT_H
typedef signed char int8_t;typedef unsigned char uint8_t;
typedef signed short int16_t;typedef unsigned short uint16_t;
typedef signed int int32_t;typedef unsigned int uint32_t;
typedef signed long long int64_t;typedef unsigned long long uint64_t;
typedef unsigned int uintptr_t;typedef int intptr_t;
#define UINT32_MAX 0xffffffffU
#define INT32_MAX 2147483647
#define INT16_MAX 32767
#define UINT64_C(x) x##ULL
#endif
''',
'stdlib.h':'''#include <stddef.h>
void *malloc(size_t);void *calloc(size_t,size_t);void *realloc(void*,size_t);void free(void*);
void abort(void);void exit(int);int abs(int);int rand(void);int atoi(const char*);long strtol(const char*,char**,int);
''',
'string.h':'''#include <stddef.h>
void *memcpy(void*,const void*,size_t);void *memmove(void*,const void*,size_t);void *memset(void*,int,size_t);int memcmp(const void*,const void*,size_t);
size_t strlen(const char*);char *strchr(const char*,int);char *strrchr(const char*,int);int strcmp(const char*,const char*);int strncmp(const char*,const char*,size_t);
char *strcpy(char*,const char*);char *strncpy(char*,const char*,size_t);char *strdup(const char*);
''',
'stdio.h':'''#ifndef WP_STDIO_H
#define WP_STDIO_H
#include <stddef.h>
#include <stdarg.h>
typedef struct WP_FILE FILE;
extern FILE *stderr,*stdout;
#define _IOFBF 0
int setvbuf(FILE*,char*,int,size_t);
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
FILE *fopen(const char*,const char*);int fclose(FILE*);size_t fread(void*,size_t,size_t,FILE*);size_t fwrite(const void*,size_t,size_t,FILE*);
int fseek(FILE*,long,int);long ftell(FILE*);int ferror(FILE*);int fflush(FILE*);void rewind(FILE*);int rename(const char*,const char*);int remove(const char*);
int printf(const char*,...);int fprintf(FILE*,const char*,...);int snprintf(char*,size_t,const char*,...);int sprintf(char*,const char*,...);int vsnprintf(char*,size_t,const char*,va_list);int puts(const char*);
#endif
''',
'assert.h':'#define assert(x) ((void)0)\n',
'math.h':'double sin(double);double cos(double);double sqrt(double);double floor(double);double ceil(double);double pow(double,double);float sqrtf(float);float fabsf(float);\n',
}
for name,text in headers.items():(inc/name).write_text('/* Compile-only declarations. No Palm runtime implementation. */\n'+text)
tc=Path('/Users/wireproof/Developer/PalmOS/toolchains/prc-release/prc-tools-remix-macos-arm64')
flags=[str(tc/'bin/arm-palmos-gcc'),'-B'+str(tc/'lib/gcc-lib/arm-palmos/3.3.1/'),'-B'+str(tc/'arm-palmos/bin/'),'-std=gnu99','-march=armv4','-O2','-fno-strict-aliasing','-I'+str(inc),'-I'+str(p),'-DZELDA_NATIVE_PLATFORM=1']
excluded={'main.c','config.c','opengl.c','glsl_shader.c','zelda_cpu_infra.c'}
sources=[s for s in (p/'src').glob('*.c') if s.name not in excluded]+[p/'snes'/name for name in ['ppu.c','dsp.c','dma.c']]
def probe(s):
 obj=out/(s.stem+'.o');r=subprocess.run(flags+['-c',str(s),'-o',str(obj)],capture_output=True,text=True)
 (out/(s.stem+'.log')).write_text(r.stderr)
 errors=[l for l in r.stderr.splitlines() if 'error:' in l or 'No such file' in l]
 return {'source':str(s.relative_to(p)),'compiled':r.returncode==0,'errors':errors[:5]}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(probe,sources))
report={'purpose':'Compile-only probe using declarations without runtime implementations; not a linked or runnable Palm game','results':results,'compiled':sum(r['compiled'] for r in results),'total':len(results)}
(out/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps({'compiled':report['compiled'],'total':report['total'],'failures':[r for r in results if not r['compiled']]},indent=2))
