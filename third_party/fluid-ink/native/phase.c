/* SPDX-License-Identifier: GPL-3.0-or-later
 * Experimental volatile EPDC waveform backend. Only the verified factory A2
 * blocks in the controller's existing coherent DMA allocation are patched.
 * No register writes, kernel pointer guesses, storage writes or boot changes.
 */
#define _GNU_SOURCE
#include "phase.h"
#include "factory_pin.h"
#include "mem_access.h"
#include "kernel_locator.h"
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <poll.h>
#include <time.h>
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
#include <arm_neon.h>
#endif
#define REF_SIZE 1169654u
#define DATA_OFFSET 63u
#define DMA_SIZE 1168216u
#define BLOCK_BYTES (8u+5u*256u)
#define REG_PHYS 0x020f4000ull
struct im_phase {
 size_t size;uint32_t offsets[14];unsigned unique,budget;
 uint32_t physical,active,guardian,restored,restore_errno;
 int writer,memory_fd,kernel_route;uint32_t kernel_alias;uint8_t *map,*ram;size_t map_size;
 char report[2048];
 uint8_t *framebuffer;unsigned stride,width,height,continuous;
 uint32_t heartbeat,drive_latched,watchdog_tripped;
 /* Original file bytes follow in shared memory, visible to the supervisor. */
};
static uint64_t le64(const uint8_t *s){uint64_t v=0;for(int i=7;i>=0;i--)v=(v<<8)|s[i];return v;}
static uint64_t fingerprint(const uint8_t *s,size_t n){
 uint64_t h=14695981039346656037ull;for(size_t i=0;i<n;i++)h=(h^s[i])*1099511628211ull;return h;
}
static uint8_t *original(im_phase *p){return (uint8_t *)(p+1)+DATA_OFFSET;}
static void note(im_phase *p,const char *stage,int error){
 int saved=errno;FILE *f=fopen(p->report,"a");if(!f){errno=saved;return;}
 fprintf(f,"Fluid Ink 6.5.0: %s; errno=%d; pulses-active=%u; budget=%u; guardian=%u; restored=%u\n",stage,error,
  __atomic_load_n(&p->active,__ATOMIC_ACQUIRE),p->budget,p->guardian,p->restored);fclose(f);errno=saved;
}
static unsigned current_budget(im_phase *p){
 uint8_t *b=(uint8_t *)(p+1),*w=original(p);int temperature=20;
 FILE *f=fopen("/sys/class/graphics/fb0/temperature","r");
 if(f){if(fscanf(f,"%d",&temperature)!=1)temperature=20;fclose(f);}
 if(temperature<0||temperature>=48)temperature=20;
 unsigned ti=0;for(unsigned i=0;i<14;i++)if(temperature>=b[48+i])ti=i;
 uint64_t table=le64(w+4*8),at=le64(w+table+8*ti),frames=le64(w+at);unsigned black=0,white=0;
 for(unsigned k=0;k<frames;k++){black+=w[at+8+256*k+15]==1;white+=w[at+8+256*k+240]==2;}
 return black&&black==white&&black<=34?black:0;
}
/* Exact local reference, intentionally not a generic arbitrary-LUT loader. */
im_phase *im_phase_create(const char *reference,const char *report){
 if(!reference||!report||strlen(report)>=2048){errno=EINVAL;return NULL;}
 int fd=open(reference,O_RDONLY|O_CLOEXEC);if(fd<0)return NULL;
 struct stat st;if(fstat(fd,&st)<0||!S_ISREG(st.st_mode)||st.st_size!=REF_SIZE){close(fd);errno=EINVAL;return NULL;}
 size_t size=sizeof(im_phase)+REF_SIZE;
 im_phase *p=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(p==MAP_FAILED){close(fd);return NULL;}
 memset(p,0,sizeof(*p));p->size=size;p->writer=-1;p->memory_fd=-1;strcpy(p->report,report);
 uint8_t *b=(uint8_t *)(p+1);size_t done=0;
 while(done<REF_SIZE){ssize_t got=read(fd,b+done,REF_SIZE-done);if(got<=0)break;done+=(size_t)got;}
 close(fd);
 if(done!=REF_SIZE||fingerprint(b,REF_SIZE)!=IM_FACTORY_FNV64||b[16]!=0x23||b[37]!=5||b[38]!=13||b[39]!=1||le64(b+DATA_OFFSET+48)!=DMA_SIZE){
  munmap(p,size);errno=EINVAL;return NULL;
 }
 uint8_t *w=original(p);uint64_t table=le64(w+4*8);
 if(table!=0x200){munmap(p,size);errno=EINVAL;return NULL;}
 for(unsigned t=0;t<14;t++){
  uint64_t at=le64(w+table+8*t);
  if(at>DMA_SIZE-BLOCK_BYTES||le64(w+at)<5||le64(w+at)>64){munmap(p,size);errno=EINVAL;return NULL;}
  unsigned i;for(i=0;i<p->unique;i++)if(p->offsets[i]==at)break;
  if(i==p->unique)p->offsets[p->unique++]=(uint32_t)at;
 }
 /* Factory endpoints are symmetric for this file. Keep their active pulse
  * budget at the current measured temperature; never infer optical feedback. */
 p->budget=current_budget(p);
 if(!p->budget){munmap(p,size);errno=EINVAL;return NULL;}
 note(p,"REFERENCE verified; RAM unchanged",0);return p;
}
static int in_ram(uint32_t address){
 FILE *f=fopen("/proc/iomem","r");if(!f)return 0;
 char line[512],label[256];unsigned long long lo,hi;int yes=0;
 while(fgets(line,sizeof(line),f))if(sscanf(line," %llx-%llx : %255[^\n]",&lo,&hi,label)==3&&!strcmp(label,"System RAM")){
  if(address>=lo&&(uint64_t)address+DMA_SIZE<=hi+1){yes=1;break;}
 }
 fclose(f);return yes;
}
static void unmap_ram(im_phase *p){
 if(p->map){munmap(p->map,p->map_size);p->map=NULL;p->ram=NULL;p->map_size=0;}
}
static int kernel_read(void *opaque,uint32_t at,void *out,size_t size){
 int fd=*(int*)opaque;return pread64(fd,out,size,(off64_t)at)==(ssize_t)size?0:-1;
}
int im_phase_preflight(im_phase *p){
 if(!p){errno=ENOENT;return -1;}
 if(p->memory_fd>=0)return 0;
 FILE *report=fopen(p->report,"a");
 int fd=im_open_memory_device(report);p->kernel_route=0;
 if(fd<0&&(errno==ENXIO||errno==ENOENT)){
  fd=im_open_kernel_memory_device(report);p->kernel_route=1;
  if(fd>=0){
   FILE *symbols=fopen("/proc/kallsyms","r"),*iomem=fopen("/proc/iomem","r");
   int rc=im_kernel_locate(symbols,iomem,kernel_read,&fd,original(p),&p->physical,&p->kernel_alias,report),error=errno;
   if(symbols)fclose(symbols);
   if(iomem)fclose(iomem);
   if(rc<0){close(fd);fd=-1;errno=error;}
  }
 }
 int saved=errno;if(report)fclose(report);errno=saved;
 if(fd<0){note(p,"PREFLIGHT memory interface unavailable; no baseline refresh",saved);return -1;}
 p->memory_fd=fd;return 0;
}
int im_phase_probe(im_phase *p){
 if(!p){errno=ENOENT;return -1;}
 if(__atomic_load_n(&p->active,__ATOMIC_ACQUIRE)){errno=EBUSY;return -1;}
 unmap_ram(p);
 if(im_phase_preflight(p)<0)return -1;
 int fd=p->memory_fd;p->memory_fd=-1;
 struct stat st;if(fstat(fd,&st)<0||!S_ISCHR(st.st_mode)){close(fd);errno=ENODEV;return -1;}
 uint32_t physical=p->physical,mapping_address=p->kernel_alias;
 if(!p->kernel_route){
 volatile uint32_t *reg=mmap64(NULL,4096,PROT_READ,MAP_SHARED,fd,(off64_t)REG_PHYS);
 if(reg==MAP_FAILED){close(fd);note(p,"PROBE register mapping refused",errno);return -1;}
 uint32_t control=reg[0],version=reg[0x7f0/4],resolution=reg[0x40/4],format=reg[0x50/4];physical=reg[0x20/4];
 munmap((void*)reg,4096);
 FILE *detail=fopen(p->report,"a");
 if(detail){fprintf(detail,"EPDC read-only probe: control=0x%08x version=0x%08x resolution=0x%08x format=0x%08x\n",control,version,resolution,format);fclose(detail);}
 unsigned major=version>>24;
 if((control&0xc00000f0u)||(major!=1&&major!=2)||
    (resolution!=((1024u<<16)|758u)&&resolution!=((758u<<16)|1024u))||
    (format&0x1000703u)!=0x400u||physical%8||!in_ram(physical)){
  close(fd);note(p,"PROBE controller/layout validation refused",ENODEV);errno=ENODEV;return -1;
 }
 mapping_address=physical;
 }else if(!in_ram(physical)){
  close(fd);note(p,"PROBE kernel DMA outside declared RAM",ENODEV);errno=ENODEV;return -1;
 }
 long page=sysconf(_SC_PAGESIZE);if(page<=0){close(fd);errno=EINVAL;return -1;}
 uint32_t base=mapping_address-(mapping_address%(uint32_t)page);size_t delta=mapping_address-base;
 size_t length=((DMA_SIZE+delta+(size_t)page-1)/(size_t)page)*(size_t)page;
 uint8_t *map=mmap64(NULL,length,PROT_READ,MAP_SHARED,fd,(off64_t)base);close(fd);
 if(map==MAP_FAILED){note(p,"PROBE DMA read mapping refused",errno);return -1;}
 /* Full byte comparison of the live, driver-owned allocation before enabling
  * write access. No scan for memory and no guessed waveform physical address. */
 if(memcmp(map+delta,original(p),DMA_SIZE)){munmap(map,length);note(p,"PROBE live/reference mismatch; no RAM write",EINVAL);errno=EINVAL;return -1;}
 if(mprotect(map,length,PROT_READ|PROT_WRITE)<0){munmap(map,length);note(p,"PROBE write protection retained",errno);return -1;}
 p->map=map;p->map_size=length;p->ram=map+delta;p->physical=physical;
 note(p,"PROBE live DMA matches factory reference; no RAM write yet",0);return 0;
}
static void copy_volatile(uint8_t *to,const uint8_t *from,size_t n){
 volatile uint8_t *dst=to;for(size_t i=0;i<n;i++)dst[i]=from[i];__sync_synchronize();
}
static void patch_blocks(im_phase *p,unsigned pulses){
 uint8_t block[BLOCK_BYTES];memset(block,0,sizeof(block));block[0]=(uint8_t)(pulses+(p->continuous?0:1));
 for(unsigned f=0;f<pulses;f++)for(unsigned source=0;source<16;source++)for(unsigned dose=1;dose<=4;dose++){
  unsigned effective=pulses==2?1+((dose-1)&1):dose;
  if(f<effective){block[8+f*256+(dose-1)*16+source]=1;block[8+f*256+(16-dose)*16+source]=2;}
 }
 /* Normally levels 0..3 select up to 1..4 black pulses, 15..12 white.
  * Pulse-2 duplicates the one/two-dose commands in the second pair;
  * pulse-1 naturally makes each used pair equivalent. These aliases
  * let PARTIAL see a logical transition on every repeated active dose.
  * Levels 4..11, including 7, are HOLD for every old state.
  * Rapide/Budget/Ref keep a final HOLD phase. Continu leaves the last
  * active phase present and requires a subsequent all-HOLD command scan. */
 for(unsigned i=0;i<p->unique;i++)copy_volatile(p->ram+p->offsets[i],block,BLOCK_BYTES);
}
static int restore_blocks(im_phase *p){
 for(unsigned i=0;i<p->unique;i++)copy_volatile(p->ram+p->offsets[i],original(p)+p->offsets[i],BLOCK_BYTES);
 for(unsigned i=0;i<p->unique;i++)if(memcmp(p->ram+p->offsets[i],original(p)+p->offsets[i],BLOCK_BYTES)){errno=EIO;return -1;}
 __atomic_store_n(&p->active,0,__ATOMIC_RELEASE);__atomic_store_n(&p->restored,1,__ATOMIC_RELEASE);
 note(p,"RESTORED original A2 blocks; verified",0);return 0;
}
void im_phase_du_primed(im_phase *p,unsigned elapsed_us){
 if(!p)return;
 char stage[160];snprintf(stage,sizeof(stage),"PRIME stock DU completed in %u us before custom A2 activation",elapsed_us);note(p,stage,0);
}
static uint32_t clock_ms(void){
 struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return (uint32_t)((uint64_t)t.tv_sec*1000+t.tv_nsec/1000000);
}
int im_phase_output(im_phase *p,uint8_t *fb,unsigned stride,unsigned width,unsigned height){
 if(!p||p->active||!fb||width!=758||height!=1024||stride<width||stride>8192){errno=EINVAL;return -1;}
 p->framebuffer=fb;p->stride=stride;p->width=width;p->height=height;return 0;
}
void im_phase_heartbeat(im_phase *p){if(p)__atomic_store_n(&p->heartbeat,clock_ms(),__ATOMIC_RELEASE);}
void im_phase_latch(im_phase *p,int active){if(p){im_phase_heartbeat(p);__atomic_store_n(&p->drive_latched,active!=0,__ATOMIC_RELEASE);}}
/* Called only after draining/terminating the renderer. The short waveform's
 * HOLD code is independent of every previous logical level. No factory mode
 * is used until a complete neutral scan and the TCE flush have succeeded. */
static int neutralize(im_phase *p,int fd,uint32_t wait_ioctl,uint32_t *next_marker){
 if(!p->continuous)return 0;
 if(!p->framebuffer){errno=EINVAL;return -1;}
 for(unsigned y=0;y<p->height;y++)memset(p->framebuffer+(size_t)y*p->stride,112,p->width);
 __sync_synchronize();
 struct {uint32_t top,left,width,height,wave,mode,marker;int32_t temp;uint32_t rest[9];} update={0};
 _Static_assert(sizeof(update)==68,"NTX update size");
 update.width=p->width;update.height=p->height;update.wave=4;update.mode=1;update.temp=4096;
 update.marker=0x40000000u+__atomic_add_fetch(next_marker,1,__ATOMIC_ACQ_REL);
 int rc;do{rc=ioctl(fd,0x4044462eu,&update);}while(rc<0&&errno==EINTR);
 if(rc>=0)do{rc=ioctl(fd,wait_ioctl,&update.marker);}while(rc<0&&errno==EINTR);
 if(rc>=0){uint32_t scheme=0;do{rc=ioctl(fd,0x40044632u,&scheme);}while(rc<0&&errno==EINTR);}
 if(rc>=0){im_phase_latch(p,0);note(p,"NEUTRAL all-HOLD ending delivered before restoration",0);}
 return rc<0?-1:0;
}
unsigned im_phase_watchdog(im_phase *p){return p?__atomic_load_n(&p->watchdog_tripped,__ATOMIC_ACQUIRE):0;}
int im_phase_restore_state(im_phase *p){
 if(!p)return 1;
 if(__atomic_load_n(&p->restore_errno,__ATOMIC_ACQUIRE))return -1;
 return __atomic_load_n(&p->active,__ATOMIC_ACQUIRE)?0:1;
}
int im_phase_begin(im_phase *p,int fbfd,uint32_t wait_ioctl,uint32_t *next_marker,unsigned pulses,int continuous){
 if(!p||!p->ram||(pulses!=1&&pulses!=2&&pulses!=4)){errno=EINVAL;return -1;}
 if(continuous&&(!p->framebuffer||
    !((continuous==IM_PHASE_CONTINUOUS&&pulses==2)||(continuous==IM_PHASE_SINGLE_TRIAL&&pulses==1)))){
  errno=ENOTSUP;return -1;
 }
 if(p->active||memcmp(p->ram,original(p),DMA_SIZE)){errno=EBUSY;return -1;}
 p->continuous=continuous!=0;p->drive_latched=0;p->watchdog_tripped=0;im_phase_heartbeat(p);
 p->budget=current_budget(p);if(!p->budget){errno=EINVAL;return -1;}
 int channel[2],ready[2];if(pipe(channel)<0)return -1;
 if(pipe(ready)<0){close(channel[0]);close(channel[1]);return -1;}
 p->restored=0;p->restore_errno=0;
 pid_t renderer=getpid();
 pid_t guardian=fork();
 if(guardian<0){close(channel[0]);close(channel[1]);close(ready[0]);close(ready[1]);return -1;}
 if(!guardian){
  close(channel[1]);close(ready[0]);
  /* KOReader can kill a renderer's entire process group. The restorer must
   * have its own group so that SIGKILL of that renderer cannot kill it too. */
  if(setpgid(0,0)<0){close(ready[1]);_exit(2);}
  char armed=1;if(write(ready[1],&armed,1)!=1)_exit(2);close(ready[1]);
  /* This process outlives a killed renderer or KOReader. EOF is the restore
   * signal. Continuous mode also neutralizes via the regular update ioctl
   * before restoring. It never changes controller registers directly. */
  signal(SIGTERM,SIG_IGN);signal(SIGINT,SIG_IGN);
  char token;
  if(p->continuous){
   struct pollfd watch={.fd=channel[0],.events=POLLIN|POLLHUP};
   for(;;){
    int polled=poll(&watch,1,25);if(polled<0&&errno==EINTR)continue;
    if(polled!=0)break;
    if(__atomic_load_n(&p->drive_latched,__ATOMIC_ACQUIRE)&&
       (uint32_t)(clock_ms()-__atomic_load_n(&p->heartbeat,__ATOMIC_ACQUIRE))>250){
     __atomic_store_n(&p->watchdog_tripped,1,__ATOMIC_RELEASE);
     note(p,"WATCHDOG renderer heartbeat stale; stopping before neutral ending",ETIMEDOUT);
     if(getppid()==renderer)kill(renderer,SIGKILL);
     break;
    }
   }
  }else while(read(channel[0],&token,1)<0&&errno==EINTR){}
  close(channel[0]);
  uint32_t marker=0x40000000u+__atomic_load_n(next_marker,__ATOMIC_ACQUIRE);
  int rc;do{rc=ioctl(fbfd,wait_ioctl,&marker);}while(rc<0&&errno==EINTR);
  /* Kobo returns success for an unknown/already removed marker. Reasserting
   * the existing SNAPSHOT scheme additionally flushes all driver updates. */
  /* Kobo returns positive remaining jiffies on a successful wait. */
  if(rc>=0){uint32_t scheme=0;do{rc=ioctl(fbfd,0x40044632u,&scheme);}while(rc<0&&errno==EINTR);}
  if(rc<0){p->restore_errno=(uint32_t)errno;note(p,"RESTORE wait failed; reboot required",errno);_exit(1);}
  if(rc>=0)rc=neutralize(p,fbfd,wait_ioctl,next_marker);
  if(rc<0){p->restore_errno=(uint32_t)errno;note(p,"RESTORE neutral ending failed; reboot required",errno);_exit(1);}
  int restored=restore_blocks(p);if(restored<0)p->restore_errno=(uint32_t)errno;
  _exit(restored<0?1:0);
 }
 close(channel[0]);close(ready[1]);char armed=0;ssize_t got;
 do{got=read(ready[0],&armed,1);}while(got<0&&errno==EINTR);close(ready[0]);
 if(got!=1||armed!=1){close(channel[1]);waitpid(guardian,NULL,0);errno=ECHILD;return -1;}
 p->writer=channel[1];p->guardian=(uint32_t)guardian;
 __atomic_store_n(&p->active,pulses,__ATOMIC_RELEASE);
 patch_blocks(p,pulses);note(p,p->continuous?"ACTIVE continuous A2 blocks; explicit HOLD ending and watchdog":"ACTIVE temporary A2 pulse blocks",0);return 0;
}
int im_phase_end(im_phase *p){
 if(!p)return 0;
 if(p->memory_fd>=0){close(p->memory_fd);p->memory_fd=-1;}
 if(p->writer>=0){close(p->writer);p->writer=-1;}
 if(p->guardian){int status;pid_t got;do{got=waitpid((pid_t)p->guardian,&status,0);}while(got<0&&errno==EINTR);
  if(got>0)p->guardian=0;
 }
 if(p->active){errno=p->restore_errno?p->restore_errno:EIO;return -1;}
 unmap_ram(p);return 0;
}
int im_phase_recover(im_phase *p){
 if(!p)return 0;
 /* Parent-side barrier after renderer exit. The independent supervisor owns
  * restoration; never dereference a mapping created in another process. */
 for(unsigned i=0;i<3000&&__atomic_load_n(&p->active,__ATOMIC_ACQUIRE);i++)usleep(1000);
 if(p->active){errno=p->restore_errno?p->restore_errno:ETIMEDOUT;note(p,"RESTORE not acknowledged; reboot required",errno);return -1;}
 return 0;
}
void im_phase_destroy(im_phase *p){if(p){im_phase_recover(p);munmap(p,p->size);}}
unsigned im_phase_budget(im_phase *p){return p?p->budget:0;}
unsigned im_phase_plan(const uint8_t *target,const uint8_t *level,uint8_t *command,size_t n,unsigned budget,unsigned pulses){
 unsigned active=0;
 for(size_t i=0;i<n;i++){
  uint8_t c=112;
  if(!target[i]&&level[i]){unsigned dose=level[i]<pulses?level[i]:pulses;c=(uint8_t)(16*(dose-1));}
  if(target[i]&&level[i]<budget){unsigned left=budget-level[i],dose=left<pulses?left:pulses;c=(uint8_t)(240-16*(dose-1));}
  command[i]=c;active+=c!=112;
 }
 return active;
}
void im_phase_commit(uint8_t *level,const uint8_t *command,size_t n,unsigned budget,unsigned pulses){
 for(size_t i=0;i<n;i++){
  unsigned code=command[i]>>4;
  if((command[i]&15)==0&&code<4){unsigned dose=code+1;if(dose<=pulses)level[i]=(uint8_t)(level[i]>dose?level[i]-dose:0);}
  else if((command[i]&15)==0&&code>=12){unsigned dose=16-code;if(dose<=pulses)level[i]=(uint8_t)(level[i]+dose<budget?level[i]+dose:budget);}
 }
}
/* InkBoy-style target budgets: a reversal restarts the endpoint budget,
 * rather than trusting a linear pigment-position estimate. */
unsigned im_drive_plan(const uint8_t *target,uint8_t *last,uint8_t *remaining,uint8_t *command,size_t n,unsigned budget,unsigned pulses,unsigned alias){
 unsigned pending=0;
 for(size_t i=0;i<n;i++){
  uint8_t next=target[i]?255:0;
  if(next!=last[i]){last[i]=next;remaining[i]=(uint8_t)budget;}
  unsigned dose=remaining[i]<pulses?remaining[i]:pulses;
  uint8_t code=!dose?112:next?(uint8_t)(240-16*(dose-1)):(uint8_t)(16*(dose-1));
  if(dose&&pulses<=2&&alias)code^=(pulses==1?16:32);
  command[i]=code;pending+=dose!=0;
 }
 return pending;
}
void im_drive_commit(uint8_t *remaining,const uint8_t *command,size_t n,unsigned pulses){
 for(size_t i=0;i<n;i++)if(command[i]!=112)remaining[i]=(uint8_t)(remaining[i]>pulses?remaining[i]-pulses:0);
}

/* The reference above is retained byte-for-byte as a comparison policy.
 * V3 executes 16 independent 8-bit controllers per NEON vector. No optical
 * coefficients change here; only confirmed-delivery bookkeeping is faster. */
unsigned im_drive_plan_fast(const uint8_t *target,uint8_t *last,uint8_t *remaining,uint8_t *command,size_t n,unsigned budget,unsigned pulses,unsigned alias){
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 size_t i=0;uint32x4_t count=vdupq_n_u32(0);
 uint8x16_t zero=vdupq_n_u8(0),one=vdupq_n_u8(1),hold=vdupq_n_u8(112),white=vdupq_n_u8(240);
 uint8x16_t cap=vdupq_n_u8((uint8_t)pulses),full=vdupq_n_u8((uint8_t)budget);
 uint8x16_t toggle=vdupq_n_u8((uint8_t)(alias&&pulses<=2?(pulses==1?16:32):0));
 for(;i+16<=n;i+=16){
  uint8x16_t next=vmvnq_u8(vceqq_u8(vld1q_u8(target+i),zero));
  uint8x16_t changed=vmvnq_u8(vceqq_u8(next,vld1q_u8(last+i)));
  uint8x16_t left=vbslq_u8(changed,full,vld1q_u8(remaining+i));
  uint8x16_t active=vmvnq_u8(vceqq_u8(left,zero)),dose=vminq_u8(left,cap);
  uint8x16_t black=vshlq_n_u8(vsubq_u8(dose,one),4);
  uint8x16_t code=veorq_u8(vbslq_u8(next,vsubq_u8(white,black),black),toggle);
  vst1q_u8(last+i,next);vst1q_u8(remaining+i,left);vst1q_u8(command+i,vbslq_u8(active,code,hold));
  count=vaddq_u32(count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(active,7))));
 }
 return im_drive_plan(target+i,last+i,remaining+i,command+i,n-i,budget,pulses,alias)+
  vgetq_lane_u32(count,0)+vgetq_lane_u32(count,1)+vgetq_lane_u32(count,2)+vgetq_lane_u32(count,3);
#else
 return im_drive_plan(target,last,remaining,command,n,budget,pulses,alias);
#endif
}
unsigned im_drive_prepare(const uint8_t *target,uint8_t *last,const uint8_t *remaining,uint8_t *command,uint8_t *after,size_t n,unsigned budget,unsigned pulses,unsigned alias){
 size_t i=0;unsigned pending=0;
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 uint32x4_t count=vdupq_n_u32(0);
 uint8x16_t zero=vdupq_n_u8(0),one=vdupq_n_u8(1),hold=vdupq_n_u8(112),white=vdupq_n_u8(240);
 uint8x16_t cap=vdupq_n_u8((uint8_t)pulses),full=vdupq_n_u8((uint8_t)budget);
 uint8x16_t toggle=vdupq_n_u8((uint8_t)(alias&&pulses<=2?(pulses==1?16:32):0));
 for(;i+16<=n;i+=16){
  uint8x16_t next=vmvnq_u8(vceqq_u8(vld1q_u8(target+i),zero));
  uint8x16_t changed=vmvnq_u8(vceqq_u8(next,vld1q_u8(last+i)));
  uint8x16_t left=vbslq_u8(changed,full,vld1q_u8(remaining+i));
  uint8x16_t active=vmvnq_u8(vceqq_u8(left,zero)),dose=vminq_u8(left,cap);
  uint8x16_t black=vshlq_n_u8(vsubq_u8(dose,one),4);
  uint8x16_t code=veorq_u8(vbslq_u8(next,vsubq_u8(white,black),black),toggle);
  vst1q_u8(last+i,next);vst1q_u8(command+i,vbslq_u8(active,code,hold));
  vst1q_u8(after+i,vqsubq_u8(left,cap));
  count=vaddq_u32(count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(active,7))));
 }
 pending=vgetq_lane_u32(count,0)+vgetq_lane_u32(count,1)+vgetq_lane_u32(count,2)+vgetq_lane_u32(count,3);
#endif
 for(;i<n;i++){
  uint8_t next=target[i]?255:0;
  unsigned left=next!=last[i]?budget:remaining[i],dose=left<pulses?left:pulses;
  uint8_t code=!dose?112:next?(uint8_t)(240-16*(dose-1)):(uint8_t)(16*(dose-1));
  if(dose&&pulses<=2&&alias)code^=(pulses==1?16:32);
  last[i]=next;command[i]=code;after[i]=(uint8_t)(left-dose);pending+=dose!=0;
 }
 return pending;
}
unsigned im_drive_prepare_white(const uint8_t *target,uint8_t *last,const uint8_t *remaining,uint8_t *command,uint8_t *after,size_t n,unsigned budget,unsigned pulses,unsigned alias,unsigned extra){
 size_t i=0;unsigned pending=0;
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 uint32x4_t count=vdupq_n_u32(0);
 uint8x16_t zero=vdupq_n_u8(0),one=vdupq_n_u8(1),hold=vdupq_n_u8(112),white=vdupq_n_u8(240);
 uint8x16_t cap=vdupq_n_u8((uint8_t)pulses),full=vdupq_n_u8((uint8_t)budget);
 uint8x16_t white_full=vdupq_n_u8((uint8_t)(budget+extra));
 uint8x16_t toggle=vdupq_n_u8((uint8_t)(alias&&pulses<=2?(pulses==1?16:32):0));
 for(;i+16<=n;i+=16){
  uint8x16_t next=vmvnq_u8(vceqq_u8(vld1q_u8(target+i),zero));
  uint8x16_t changed=vmvnq_u8(vceqq_u8(next,vld1q_u8(last+i)));
  uint8x16_t left=vbslq_u8(changed,vbslq_u8(next,white_full,full),vld1q_u8(remaining+i));
  uint8x16_t active=vmvnq_u8(vceqq_u8(left,zero)),dose=vminq_u8(left,cap);
  uint8x16_t black=vshlq_n_u8(vsubq_u8(dose,one),4);
  uint8x16_t code=veorq_u8(vbslq_u8(next,vsubq_u8(white,black),black),toggle);
  vst1q_u8(last+i,next);vst1q_u8(command+i,vbslq_u8(active,code,hold));
  vst1q_u8(after+i,vqsubq_u8(left,cap));
  count=vaddq_u32(count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(active,7))));
 }
 pending=vgetq_lane_u32(count,0)+vgetq_lane_u32(count,1)+vgetq_lane_u32(count,2)+vgetq_lane_u32(count,3);
#endif
 for(;i<n;i++){
  uint8_t next=target[i]?255:0;
  unsigned left=next!=last[i]?budget+(next?extra:0):remaining[i],dose=left<pulses?left:pulses;
  uint8_t code=!dose?112:next?(uint8_t)(240-16*(dose-1)):(uint8_t)(16*(dose-1));
  if(dose&&pulses<=2&&alias)code^=(pulses==1?16:32);
  last[i]=next;command[i]=code;after[i]=(uint8_t)(left-dose);pending+=dose!=0;
 }
 return pending;
}
void im_drive_commit_fast(uint8_t *remaining,const uint8_t *command,size_t n,unsigned pulses){
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 size_t i=0;uint8x16_t hold=vdupq_n_u8(112),cap=vdupq_n_u8((uint8_t)pulses);
 for(;i+16<=n;i+=16){
  uint8x16_t left=vld1q_u8(remaining+i),idle=vceqq_u8(vld1q_u8(command+i),hold);
  vst1q_u8(remaining+i,vbslq_u8(idle,left,vqsubq_u8(left,cap)));
 }
 im_drive_commit(remaining+i,command+i,n-i,pulses);
#else
 im_drive_commit(remaining,command,n,pulses);
#endif
}
