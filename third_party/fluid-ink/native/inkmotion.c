/* SPDX-License-Identifier: GPL-3.0-or-later
 * Native mailbox, NEON quantizer, stock transport and optional volatile pulses.
 * Single producer (KOReader), single consumer (forked worker).
 * Slot ownership uses acquire/release atomics, including on ARMv7.
 */
#define _GNU_SOURCE
#include "inkmotion.h"
#include "phase.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sched.h>
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
#include <arm_neon.h>
#endif

#define LOAD(p) __atomic_load_n((p), __ATOMIC_ACQUIRE)
#define STORE(p,v) __atomic_store_n((p),(v),__ATOMIC_RELEASE)
#define ADD(p,v) __atomic_fetch_add((p),(v),__ATOMIC_RELAXED)
enum { FREE, WRITING, READY, READING };
enum { IDLE=1, QUANTIZE, SUBMIT, WAIT, CLEAN, STOPPED, ERROR_STATE };
enum { BAND_ROWS=16, POSITION_BANDS=64 };
enum { FLUID=12, FLUID_WHITE=13, FLUID_FAST=14, FLUID_REGIONAL=15 };
enum { FLUID_GRAY_MARGIN=8, FLUID_WHITE_EXTENSION=4, FLUID_REBASE_PULSES=24, FLUID_SETTLE_US=350000 };
typedef struct { uint32_t state, seq; int wave, dither, gamma, window;uint64_t created_us; } slot;
/* Fixed-width NTX ioctl ABI, including its 32-bit virtual-address placeholder.
 * Do not use native void* here: tests also run on a 64-bit host. */
typedef struct {
    uint32_t top,left,width,height,wave,mode,marker;
    int32_t temp;
    uint32_t flags,virt,phys,aw,ah,atop,aleft,awidth,aheight;
} ntx_update;
_Static_assert(sizeof(ntx_update)==68, "NTX ABI must be 68 bytes");
enum { SEND_NTX=0x4044462e, SEND_V2=0x4048462e };
/* The 72-byte Kobo and Kindle structures share the initial rectangle,
 * waveform, mode and marker. The next four words have different meanings. */
typedef struct {
    uint32_t top,left,width,height,wave,mode,marker;
    uint32_t fields[4], alt[7];
} v2_update;
_Static_assert(sizeof(v2_update)==72,"v2 ABI must be 72 bytes");
struct im_context {
    im_config cfg;
    uint32_t stop, pause, clean, sequence, queue_window, capture, phase_settings;
    slot slots[3];
    im_stats stats;
    uint8_t noise[4096], linear[256];
    /* Shared slots follow this header; private scratch is inherited on fork. */
    uint8_t *output;
    uint8_t *commands,*levels,*targets,*remaining;
    uint8_t *pending_remaining,*prepared_remaining;
    /* The position mode reuses the three budget images. A band selects its
     * own bank, so skipping settled bands does not copy their history. */
    uint8_t position_bank[POSITION_BANDS], pending_bank[POSITION_BANDS], next_bank[POSITION_BANDS];
    uint64_t position_busy, pending_busy, next_busy, command_bands, framebuffer_bands;
    int position_dither,position_gamma;
    unsigned position_invalid;
    uint32_t still;
    int retained_source;
    unsigned current_policy,alias;
    im_phase *phase;
    unsigned active_pulses,pulse_pending,continuous_dirty;
    size_t bytes, mapping_size;
    int valid;
    uint32_t markers[8], head, count, next_marker,last_source_seq;uint64_t source_created;
    pid_t owner;
};
static const uint8_t bayer[64]={
 0,48,12,60,3,51,15,63,32,16,44,28,35,19,47,31,
 8,56,4,52,11,59,7,55,40,24,36,20,43,27,39,23,
 2,50,14,62,1,49,13,61,34,18,46,30,33,17,45,29,
 10,58,6,54,9,57,5,53,42,26,38,22,41,25,37,21};
static int continuous_policy(unsigned policy){return policy==3||policy==4||policy>=6;}
static int pipeline_policy(unsigned policy){return policy>=6;}
static int position_policy(unsigned policy){return policy>=10;}
static int fluid_policy(unsigned policy){return policy>=FLUID;}
static int single_phase_policy(unsigned policy){return policy==11||policy==FLUID_FAST||policy==FLUID_REGIONAL;}
static unsigned position_limit(unsigned policy,unsigned budget){
    return budget+(policy>=FLUID_WHITE?FLUID_WHITE_EXTENSION:0);
}
static unsigned phase_style(unsigned policy,unsigned pulses){
    if(single_phase_policy(policy)&&pulses==1)return IM_PHASE_SINGLE_TRIAL;
    return continuous_policy(policy)&&pulses==2?IM_PHASE_CONTINUOUS:IM_PHASE_HOLD;
}
static unsigned white_extra(unsigned policy){return policy==7?2:policy==8?4:0;}
static uint64_t micros(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t);
    return (uint64_t)t.tv_sec*1000000u+(uint64_t)t.tv_nsec/1000u;
}
static int take(uint32_t *p,uint32_t old,uint32_t next) {
    return __atomic_compare_exchange_n(p,&old,next,0,__ATOMIC_ACQ_REL,__ATOMIC_ACQUIRE);
}
static uint8_t *pixels(im_context *c,int i) { return (uint8_t *)(c+1)+c->bytes*i; }
int im_version(void) { return 6500; }
unsigned im_abi_size(unsigned which) { return which==0?sizeof(im_config):which==1?sizeof(im_stats):0; }
im_context *im_create(const im_config *p,const uint8_t *noise) {
    if(!p||!noise||!p->framebuffer||p->transport>IM_KINDLE_CARTA||
       (p->transport!=IM_AURA2&&p->wait_ioctl!=(p->transport==IM_KOBO_NTX?0x4004462fu:0xc008462fu))||
       (p->wake_epdc&&(p->transport!=IM_KOBO_NTX&&p->transport!=IM_KOBO_MK7))||
       p->width<2||p->height<2||p->width>4096||p->height>4096||
       p->rotation<0||p->rotation>3||(p->bpp!=8&&p->bpp!=16)||
       p->physical_width<2||p->physical_height<2||
       p->stride<p->physical_width*(p->bpp/8)||
       p->width!=((p->rotation&1)?p->physical_height:p->physical_width)||
       p->height!=((p->rotation&1)?p->physical_width:p->physical_height)) {errno=EINVAL;return NULL;}
    size_t n=(size_t)p->width*p->height, size=sizeof(im_context)+3*n;
    im_context *c=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
    if(c==MAP_FAILED)return NULL;
    memset(c,0,sizeof(*c));c->cfg=*p;c->bytes=n;c->mapping_size=size;c->owner=getpid();
    c->retained_source=-1;
    c->output=malloc(n);c->commands=malloc(n);c->levels=malloc(n);c->targets=malloc(n);c->remaining=malloc(n);c->phase_settings=2u<<8;
    c->pending_remaining=malloc(n);c->prepared_remaining=malloc(n);
    if(!c->output||!c->commands||!c->levels||!c->targets||!c->remaining||!c->pending_remaining||!c->prepared_remaining){free(c->output);free(c->commands);free(c->levels);free(c->targets);free(c->remaining);free(c->pending_remaining);free(c->prepared_remaining);munmap(c,size);return NULL;}
    memset(c->output,255,n);
    memcpy(c->noise,noise,4096);
    /* Integer gamma ~2: monotonic LUT, endpoints exact. No libm at runtime. */
    for(int i=0;i<256;i++)c->linear[i]=(uint8_t)((i*i+127)/255);
    return c;
}
int im_publish(im_context *c,const uint8_t *src,int stride,int wave,int dither,int gamma,int window) {
    if(!c||!src||stride<c->cfg.width||wave<0||wave>1||dither<0||dither>3||
       gamma<0||gamma>1||window<1||window>8)return -1;
    int selected=-1;
    for(int i=0;i<3;i++)if(take(&c->slots[i].state,FREE,WRITING)){selected=i;break;}
    if(selected<0)for(int i=0;i<3;i++)if(take(&c->slots[i].state,READY,WRITING)){
        selected=i;ADD(&c->stats.overwritten,1);break;
    }
    if(selected<0)return 0;
    uint8_t *dst=pixels(c,selected);
    for(int y=0;y<c->cfg.height;y++)memcpy(dst+(size_t)y*c->cfg.width,src+(size_t)y*stride,c->cfg.width);
    slot *s=&c->slots[selected];
    s->wave=wave;s->dither=dither;s->gamma=gamma;s->window=window;
    s->created_us=micros();s->seq=++c->sequence;STORE(&c->queue_window,window);ADD(&c->stats.published,1);
    STORE(&s->state,READY);return 1;
}
void im_read_stats(im_context *c,im_stats *s) {
    uint32_t *src=(uint32_t *)&c->stats,*dst=(uint32_t *)s;
    for(size_t i=0;i<sizeof(*s)/4;i++)dst[i]=LOAD(src+i);
}
void im_clean(im_context *c){ADD(&c->clean,1);}
void im_pause(im_context *c,int p){STORE(&c->pause,p!=0);}
int im_pause_ack(im_context *c){return LOAD(&c->stats.paused)!=0;}
void im_stop(im_context *c){STORE(&c->stop,1);}
void im_set_capture(im_context *c,int on){STORE(&c->capture,c->cfg.transport==IM_AURA2&&on!=0);}
int im_configure_phase(im_context *c,const char *reference,const char *report){
    if(c->cfg.transport!=IM_AURA2){errno=ENOTSUP;return -1;}
    if(c->phase){errno=EBUSY;return -1;}
    c->phase=im_phase_create(reference,report);return c->phase?0:-1;
}
static int valid_pulses(unsigned n){return n==0||n==1||n==2||n==4;}
/* Policy and phase count are one command, notably when entering the
 * explicitly selected single-phase trial. */
void im_set_presentation(im_context *c,unsigned policy,unsigned pulses,int retry){
    if(policy>FLUID_REGIONAL||!valid_pulses(pulses))return;
    if(retry)STORE(&c->stats.phase_errno,0);
    if(c->cfg.transport!=IM_AURA2||(pulses&&LOAD(&c->stats.phase_errno)))pulses=0;
    STORE(&c->phase_settings,(policy<<8)|pulses);
}
void im_set_still(im_context *c,int still){STORE(&c->still,still!=0);}
void im_set_phase(im_context *c,unsigned n){im_set_presentation(c,LOAD(&c->phase_settings)>>8,n,0);}
void im_request_phase(im_context *c,unsigned n){im_set_presentation(c,LOAD(&c->phase_settings)>>8,n,1);}
void im_set_drive_policy(im_context *c,unsigned policy){im_set_presentation(c,policy,LOAD(&c->phase_settings)&255,0);}
int im_phase_watchdog_tripped(im_context *c){return (int)im_phase_watchdog(c->phase);}
int im_phase_recovery_state(im_context *c){return im_phase_restore_state(c->phase);}
int im_restore_phase(im_context *c){return im_phase_recover(c->phase);}
void im_destroy(im_context *c){if(c){im_phase_destroy(c->phase);free(c->output);free(c->commands);free(c->levels);free(c->targets);free(c->remaining);free(c->pending_remaining);free(c->prepared_remaining);munmap(c,c->mapping_size);}}

int im_quantize_reference(im_context *c,const uint8_t *src,int stride,int dither,int gamma,
                uint8_t *out,int *rx,int *ry,int *rw,int *rh) {
    if(!c||!src||!out||stride<c->cfg.width||dither<0||dither>3||gamma<0||gamma>1)return -1;
    int w=c->cfg.width,h=c->cfg.height,x0=w,y0=h,x1=-1,y1=-1,n=0;
    for(int y=0;y<h;y++){
        const uint8_t *s=src+(size_t)y*stride;uint8_t *d=out+(size_t)y*w;
        for(int x=0;x<w;x++){
            int v=s[x];if(gamma)v=c->linear[v];
            int threshold=dither==0?(bayer[(y&7)*8+(x&7)]*4+2):
                dither==1?c->noise[(y&63)*64+(x&63)]:
                dither==2?(bayer[((y>>1)&7)*8+((x>>1)&7)]*4+2):127;
            uint8_t q=v==255?255:(v==0?0:(v>threshold?255:0));
            if(q!=d[x]){d[x]=q;n++;if(x<x0)x0=x;if(x>x1)x1=x;if(y<y0)y0=y;if(y>y1)y1=y;}
        }
    }
    if(rx)*rx=x0;
    if(ry)*ry=y0;
    if(rw)*rw=n?x1-x0+1:0;
    if(rh)*rh=n?y1-y0+1:0;
    return n;
}
int im_quantize(im_context *c,const uint8_t *src,int stride,int dither,int gamma,
                uint8_t *out,int *rx,int *ry,int *rw,int *rh) {
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
    if(!c||!src||!out||stride<c->cfg.width||dither<0||dither>3||gamma<0||gamma>1)return -1;
    if(gamma)return im_quantize_reference(c,src,stride,dither,gamma,out,rx,ry,rw,rh);
    int w=c->cfg.width,h=c->cfg.height,x0=w,x1=-1,y0=h,y1=-1,tail_count=0;
    uint32x4_t counts=vdupq_n_u32(0);
    uint8x16_t white=vdupq_n_u8(255);
    for(int y=0;y<h;y++){
        const uint8_t *s=src+(size_t)y*stride;uint8_t *d=out+(size_t)y*w;
        uint8_t row[16];
        if(dither!=1)for(int i=0;i<16;i++)row[i]=dither==3?127:
            bayer[(dither==2?((y>>1)&7):(y&7))*8+(dither==2?((i>>1)&7):(i&7))]*4+2;
        int x=0,row_changed=0;
        for(;x+16<=w;x+=16){
            uint8x16_t v=vld1q_u8(s+x);
            uint8x16_t threshold=vld1q_u8(dither==1?c->noise+(y&63)*64+(x&63):row);
            uint8x16_t q=vorrq_u8(vcgtq_u8(v,threshold),vceqq_u8(v,white));
            uint8x16_t diff=vmvnq_u8(vceqq_u8(q,vld1q_u8(d+x)));
            vst1q_u8(d+x,q);
            counts=vaddq_u32(counts,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(diff,7))));
            uint64x2_t bits=vreinterpretq_u64_u8(diff);
            uint64_t lo=vgetq_lane_u64(bits,0),hi=vgetq_lane_u64(bits,1);
            if(lo||hi){
                int first=lo?__builtin_ctzll(lo)/8:8+__builtin_ctzll(hi)/8;
                int last=hi?8+(63-__builtin_clzll(hi))/8:(63-__builtin_clzll(lo))/8;
                if(x+first<x0)x0=x+first;
                if(x+last>x1)x1=x+last;
                row_changed=1;
            }
        }
        for(;x<w;x++){
            int v=s[x];int t=dither==1?c->noise[(y&63)*64+(x&63)]:row[x&15];
            uint8_t q=v==255?255:(v>t?255:0);
            if(q!=d[x]){d[x]=q;tail_count++;if(x<x0)x0=x;if(x>x1)x1=x;row_changed=1;}
        }
        if(row_changed){if(y<y0)y0=y;y1=y;}
    }
    int n=tail_count+vgetq_lane_u32(counts,0)+vgetq_lane_u32(counts,1)+vgetq_lane_u32(counts,2)+vgetq_lane_u32(counts,3);
    if(rx)*rx=x0;
    if(ry)*ry=y0;
    if(rw)*rw=n?x1-x0+1:0;
    if(rh)*rh=n?y1-y0+1:0;
    return n;
#else
    return im_quantize_reference(c,src,stride,dither,gamma,out,rx,ry,rw,rh);
#endif
}
/* Pulse requests always cover the command image. Their quantizer needs no
 * bounding rectangle, lane extraction, CTZ/CLZ or per-vector scalar branch. */
int im_quantize_target(im_context *c,const uint8_t *src,int stride,int dither,int gamma,uint8_t *out){
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 if(!c||!src||!out||stride<c->cfg.width||dither<0||dither>3||gamma<0||gamma>1)return -1;
 if(gamma)return im_quantize_reference(c,src,stride,dither,gamma,out,NULL,NULL,NULL,NULL);
 int w=c->cfg.width,h=c->cfg.height,tail=0;uint32x4_t count=vdupq_n_u32(0);
 uint8x16_t white=vdupq_n_u8(255);
 for(int y=0;y<h;y++){
  const uint8_t *s=src+(size_t)y*stride;uint8_t *d=out+(size_t)y*w,row[16];
  if(dither!=1)for(int i=0;i<16;i++)row[i]=dither==3?127:
   bayer[(dither==2?((y>>1)&7):(y&7))*8+(dither==2?((i>>1)&7):(i&7))]*4+2;
  int x=0;
  for(;x+16<=w;x+=16){
   uint8x16_t v=vld1q_u8(s+x),t=vld1q_u8(dither==1?c->noise+(y&63)*64+(x&63):row);
   uint8x16_t q=vorrq_u8(vcgtq_u8(v,t),vceqq_u8(v,white));
   uint8x16_t changed=vmvnq_u8(vceqq_u8(q,vld1q_u8(d+x)));vst1q_u8(d+x,q);
   count=vaddq_u32(count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(changed,7))));
  }
  for(;x<w;x++){
   int v=s[x],t=dither==1?c->noise[(y&63)*64+(x&63)]:row[x&15];
   uint8_t q=v==255?255:(v>t?255:0);tail+=q!=d[x];d[x]=q;
  }
 }
 return tail+vgetq_lane_u32(count,0)+vgetq_lane_u32(count,1)+vgetq_lane_u32(count,2)+vgetq_lane_u32(count,3);
#else
 return im_quantize_reference(c,src,stride,dither,gamma,out,NULL,NULL,NULL,NULL);
#endif
}
/* One traversal for grayscale -> binary target -> next electrical command.
 * `remaining` is read-only: budgets are still committed by marker success.
 * Gamma retains the reference path; ordinary UI modes use the fused NEON loop. */
int im_quantize_prepare(im_context *c,const uint8_t *src,int stride,int dither,int gamma,uint8_t *out,
        uint8_t *last,const uint8_t *remaining,uint8_t *command,uint8_t *after,
        unsigned budget,unsigned pulses,unsigned alias,unsigned extra,unsigned *pending){
 if(!c||!src||!out||!last||!remaining||!command||!after||!pending||stride<c->cfg.width||
    dither<0||dither>3||gamma<0||gamma>1||budget<1||budget>34||
    (pulses!=1&&pulses!=2&&pulses!=4)||alias>1||(extra!=0&&extra!=2&&extra!=4))return -1;
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
 if(!gamma){
  int w=c->cfg.width,h=c->cfg.height,changed_tail=0;unsigned pending_tail=0;
  uint32x4_t changes=vdupq_n_u32(0),active_count=vdupq_n_u32(0);
  uint8x16_t white=vdupq_n_u8(255),zero=vdupq_n_u8(0),one=vdupq_n_u8(1),hold=vdupq_n_u8(112),wc=vdupq_n_u8(240);
  uint8x16_t full=vdupq_n_u8((uint8_t)budget),white_full=vdupq_n_u8((uint8_t)(budget+extra)),cap=vdupq_n_u8((uint8_t)pulses);
  uint8x16_t toggle=vdupq_n_u8((uint8_t)(alias&&pulses<=2?(pulses==1?16:32):0));
  for(int y=0;y<h;y++){
   const uint8_t *s=src+(size_t)y*stride;size_t offset=(size_t)y*w;uint8_t row[16];
   if(dither!=1)for(int i=0;i<16;i++)row[i]=dither==3?127:
       bayer[(dither==2?((y>>1)&7):(y&7))*8+(dither==2?((i>>1)&7):(i&7))]*4+2;
   int x=0;
   for(;x+16<=w;x+=16){
    size_t k=offset+x;
    uint8x16_t value=vld1q_u8(s+x),threshold=vld1q_u8(dither==1?c->noise+(y&63)*64+(x&63):row);
    uint8x16_t next=vorrq_u8(vcgtq_u8(value,threshold),vceqq_u8(value,white));
    uint8x16_t diff=vmvnq_u8(vceqq_u8(next,vld1q_u8(out+k)));
    changes=vaddq_u32(changes,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(diff,7))));
    uint8x16_t changed=vmvnq_u8(vceqq_u8(next,vld1q_u8(last+k)));
    uint8x16_t left=vbslq_u8(changed,vbslq_u8(next,white_full,full),vld1q_u8(remaining+k));
    uint8x16_t active=vmvnq_u8(vceqq_u8(left,zero)),dose=vminq_u8(left,cap);
    uint8x16_t black=vshlq_n_u8(vsubq_u8(dose,one),4);
    uint8x16_t code=veorq_u8(vbslq_u8(next,vsubq_u8(wc,black),black),toggle);
    vst1q_u8(out+k,next);vst1q_u8(last+k,next);vst1q_u8(command+k,vbslq_u8(active,code,hold));
    vst1q_u8(after+k,vqsubq_u8(left,cap));
    active_count=vaddq_u32(active_count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(active,7))));
   }
   for(;x<w;x++){
    size_t k=offset+x;int v=s[x],t=dither==1?c->noise[(y&63)*64+(x&63)]:row[x&15];
    uint8_t next=v==255?255:(v>t?255:0);changed_tail+=next!=out[k];
    unsigned left=next!=last[k]?budget+(next?extra:0):remaining[k],dose=left<pulses?left:pulses;
    uint8_t code=!dose?112:next?(uint8_t)(240-16*(dose-1)):(uint8_t)(16*(dose-1));
    if(dose&&pulses<=2&&alias)code^=(pulses==1?16:32);
    out[k]=last[k]=next;command[k]=code;after[k]=(uint8_t)(left-dose);pending_tail+=dose!=0;
   }
  }
  *pending=pending_tail+vgetq_lane_u32(active_count,0)+vgetq_lane_u32(active_count,1)+vgetq_lane_u32(active_count,2)+vgetq_lane_u32(active_count,3);
  return changed_tail+vgetq_lane_u32(changes,0)+vgetq_lane_u32(changes,1)+vgetq_lane_u32(changes,2)+vgetq_lane_u32(changes,3);
 }
#endif
 int changed=im_quantize_reference(c,src,stride,dither,gamma,out,NULL,NULL,NULL,NULL);
 if(changed<0)return changed;
 *pending=im_drive_prepare_white(out,last,remaining,command,after,c->bytes,budget,pulses,alias,extra);
 return changed;
}
/* Estimate position by integrating delivered drive, measured in phase counts.
 * A reversal retraces the distance already travelled. Endpoints provide a
 * finite bound; this model does not measure reflectance or actual charge. */
static unsigned position_band(im_context *c,const uint8_t *src,int y0,int y1,
        int dither,int gamma,const uint8_t *base,uint8_t *next,unsigned limit,int *unfinished) {
    unsigned pending=0;
    int w=c->cfg.width;
    unsigned cap=c->active_pulses;
    unsigned margin=fluid_policy(c->current_policy)&&!LOAD(&c->still)?FLUID_GRAY_MARGIN:0;
    unsigned toggle=c->alias&&cap<=2?(cap==1?16:32):0;
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
    uint32x4_t count=vdupq_n_u32(0);
    uint8x16_t busy=vdupq_n_u8(0),end=vdupq_n_u8((uint8_t)limit);
    uint8x16_t maxdose=vdupq_n_u8((uint8_t)cap),white=vdupq_n_u8(255);
    uint8x16_t hold=vdupq_n_u8(112),alias=vdupq_n_u8((uint8_t)toggle);
#endif
    for(int y=y0;y<y1;y++){
        size_t row=(size_t)y*w;
        const uint8_t *input=src?src+row:NULL;
        const uint8_t *threshold=c->noise+(y&63)*64;
        uint8_t pattern[16];
        if(input&&dither!=1){
            unsigned yy=dither==2?(y>>1)&7:y&7;
            for(int i=0;i<16;i++){
                unsigned xx=dither==2?(i>>1)&7:i&7;
                pattern[i]=dither==3?127:(uint8_t)(4*bayer[yy*8+xx]+2);
            }
        }
        int x=0;
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
        if(!input||!gamma){
            for(;x+16<=w;x+=16){
                size_t i=row+x;
                uint8x16_t q;
                if(input){
                    uint8x16_t v=vld1q_u8(input+x);
                    uint8x16_t t=vld1q_u8(dither==1?threshold+(x&63):pattern);
                    if(margin){
                        uint8x16_t m=vdupq_n_u8((uint8_t)margin);
                        t=vbslq_u8(vld1q_u8(c->output+i),vqsubq_u8(t,m),vqaddq_u8(t,m));
                    }
                    q=vorrq_u8(vcgtq_u8(v,t),vceqq_u8(v,white));
                    if(margin)q=vbicq_u8(q,vceqq_u8(v,vdupq_n_u8(0)));
                    vst1q_u8(c->output+i,q);
                }else q=vld1q_u8(c->output+i);
                uint8x16_t pos=vld1q_u8(base+i),goal=vandq_u8(q,end);
                uint8x16_t distance=vabdq_u8(goal,pos),dose=vminq_u8(distance,maxdose);
                uint8x16_t active=vcgtq_u8(distance,vdupq_n_u8(0));
                uint8x16_t code=vshlq_n_u8(vsubq_u8(dose,vdupq_n_u8(1)),4);
                code=veorq_u8(vbslq_u8(q,vsubq_u8(vdupq_n_u8(240),code),code),alias);
                vst1q_u8(c->commands+i,vbslq_u8(active,code,hold));
                vst1q_u8(next+i,vbslq_u8(q,vaddq_u8(pos,dose),vsubq_u8(pos,dose)));
                busy=vorrq_u8(busy,vcgtq_u8(distance,maxdose));
                count=vaddq_u32(count,vpaddlq_u16(vpaddlq_u8(vshrq_n_u8(active,7))));
            }
        }
#endif
        for(;x<w;x++){
            size_t i=row+x;
            if(input){
                unsigned v=gamma?c->linear[input[x]]:input[x];
                unsigned t=dither==1?threshold[x&63]:pattern[x&15];
                if(margin)t=c->output[i]?(t>margin?t-margin:0):(t+margin>255?255:t+margin);
                c->output[i]=v==255||v>t?255:0;
            }
            unsigned pos=base[i],goal=c->output[i]?limit:0;
            unsigned distance=goal?goal-pos:pos;
            unsigned dose=distance<cap?distance:cap;
            uint8_t code=112;
            if(dose)code=(uint8_t)((goal?240-16*(dose-1):16*(dose-1))^toggle);
            c->commands[i]=code;
            next[i]=(uint8_t)(goal?pos+dose:pos-dose);
            *unfinished|=distance>cap;
            pending+=dose!=0;
        }
    }
#if defined(__ARM_NEON) && !defined(IM_DISABLE_NEON)
    uint64x2_t bits=vreinterpretq_u64_u8(busy);
    *unfinished|=(vgetq_lane_u64(bits,0)|vgetq_lane_u64(bits,1))!=0;
    pending+=vgetq_lane_u32(count,0)+vgetq_lane_u32(count,1)+vgetq_lane_u32(count,2)+vgetq_lane_u32(count,3);
#endif
    return pending;
}
static uint64_t process_us(void) {
    struct timespec t;
    if(clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t)<0)return 0;
    return (uint64_t)t.tv_sec*1000000u+(uint64_t)t.tv_nsec/1000u;
}
/* Comparison uses the last image actually consumed, so replacing mailbox
 * frames cannot hide a change. Absolute rows preserve dither phase. */
static unsigned prepare_position(im_context *c,const uint8_t *src,int dither,int gamma) {
    uint64_t cpu_start=process_us();
    const int w=c->cfg.width,h=c->cfg.height;
    uint8_t *banks[]={c->remaining,c->pending_remaining,c->prepared_remaining};
    const uint8_t *base=c->pulse_pending==1?c->pending_bank:c->position_bank;
    uint64_t busy=c->pulse_pending==1?c->pending_busy:c->position_busy;
    int recheck=c->position_invalid!=0 || (src&&(dither!=c->position_dither||gamma!=c->position_gamma));
    unsigned pending=0,processed=0,saved=0;
    unsigned limit=position_limit(c->current_policy,im_phase_budget(c->phase));
    const uint8_t *previous=c->targets;
    if(fluid_policy(c->current_policy))
        previous=c->retained_source>=0?pixels(c,c->retained_source):NULL;
    c->next_busy=0;
    c->command_bands=0;
    for(int y=0,b=0;y<h;y+=BAND_ROWS,b++){
        uint64_t bit=UINT64_C(1)<<b;
        int end=y+BAND_ROWS<h?y+BAND_ROWS:h;
        size_t start=(size_t)y*w,length=(size_t)(end-y)*w;
        int changed=src&&(recheck||!previous||memcmp(src+start,previous+start,length)!=0);
        c->next_bank[b]=base[b];
        if(!changed&&!recheck&&!(busy&bit))continue;
        if(changed){
            if(!fluid_policy(c->current_policy))memcpy(c->targets+start,src+start,length);
            else saved+=(unsigned)length;
        }
        unsigned bank=(base[b]+1)%3;
        while(bank==c->position_bank[b])bank=(bank+1)%3;
        int unfinished=0;
        unsigned active=position_band(c,changed?src:NULL,y,end,dither,gamma,
                banks[base[b]],banks[bank],limit,&unfinished);
        if(active){
            c->next_bank[b]=(uint8_t)bank;
            c->command_bands|=bit;
        }
        if(unfinished)c->next_busy|=bit;
        pending+=active;
        processed+=(unsigned)length;
    }
    if(src){
        c->position_dither=dither;
        c->position_gamma=gamma;
        c->position_invalid=0;
    }
    uint64_t cpu_end=process_us();
    ADD(&c->stats.position_plans,1);
    ADD(&c->stats.position_pixels,processed);
    if(saved)ADD(&c->stats.source_copy_saved,saved);
    if(cpu_start&&cpu_end>=cpu_start)ADD(&c->stats.position_cpu_us,(uint32_t)(cpu_end-cpu_start));
    return pending;
}
static void release_source(im_context *c){
    if(c->retained_source<0)return;
    STORE(&c->slots[c->retained_source].state,FREE);
    c->retained_source=-1;
}
static void copy_position_commands(im_context *c) {
    uint64_t write=c->framebuffer_bands|c->command_bands;
    for(unsigned y=0,b=0;y<(unsigned)c->cfg.height;y+=BAND_ROWS,b++){
        uint64_t bit=UINT64_C(1)<<b;
        if(!(write&bit))continue;
        for(unsigned row=y;row<y+BAND_ROWS&&row<(unsigned)c->cfg.height;row++){
            uint8_t *dst=c->cfg.framebuffer+(size_t)row*c->cfg.stride;
            if(c->command_bands&bit)memcpy(dst,c->commands+(size_t)row*c->cfg.width,c->cfg.width);
            else memset(dst,112,c->cfg.width);
        }
    }
    c->framebuffer_bands=c->command_bands;
}
/* The next one-phase request must cover every band that just received a
 * drive command, even if its new command is HOLD. Submit a single rectangle
 * spanning these bands, so no old drive is left outside by a moving update. */
static void position_scan_rows(const im_context *c,unsigned pending,int *top,int *height){
    *top=0;
    *height=c->cfg.height;
    if(c->current_policy!=FLUID_REGIONAL||!pending)return;
    uint64_t bands=c->framebuffer_bands|c->command_bands;
    if(!bands)return;
    int first=__builtin_ctzll(bands)*BAND_ROWS;
    int end=(64-__builtin_clzll(bands))*BAND_ROWS;
    if(end>c->cfg.height)end=c->cfg.height;
    *top=first;
    *height=end-first;
}
static void fb_copy_from(im_context *c,const uint8_t *source) {
    im_config *p=&c->cfg;int w=p->width,h=p->height;
    for(int y=0;y<h;y++){
        const uint8_t *s=source+(size_t)y*w;
        if(p->rotation==0&&p->bpp==8&&!p->inverse){memcpy(p->framebuffer+(size_t)y*p->stride,s,w);continue;}
        for(int x=0;x<w;x++){
            int px=x,py=y;
            if(p->rotation==1){px=p->physical_width-y-1;py=x;}
            else if(p->rotation==2){px=p->physical_width-x-1;py=p->physical_height-y-1;}
            else if(p->rotation==3){px=y;py=p->physical_height-x-1;}
            uint8_t v=p->inverse?(s[x]^255):s[x];
            uint8_t *d=p->framebuffer+(size_t)py*p->stride+px*(p->bpp/8);
            if(p->bpp==8)*d=v;else {d[0]=v;d[1]=v;}
        }
    }
}
static void fb_copy(im_context *c){fb_copy_from(c,c->output);}
static int fail(im_context *c) {STORE(&c->stats.last_errno,errno);ADD(&c->stats.errors,1);STORE(&c->stats.state,ERROR_STATE);return -1;}
static int wait_marker(im_context *c,uint32_t marker) {
    uint64_t t=micros();STORE(&c->stats.state,WAIT);
    int rc=0;
    uint32_t marker_data[2]={marker,0};
    if(c->cfg.fd>=0)do {rc=ioctl(c->cfg.fd,c->cfg.wait_ioctl,marker_data);}while(rc<0&&errno==EINTR&&!LOAD(&c->stop));
    ADD(&c->stats.wait_us,(uint32_t)(micros()-t));ADD(&c->stats.waits,1);
    if(rc<0)return fail(c);
    return 0;
}
static int wait_oldest(im_context *c) {
    if(!c->count)return 0;
    if(wait_marker(c,c->markers[c->head])<0)return -1;
    if(c->pulse_pending){
        uint64_t commit_start=micros();
        if(c->pulse_pending==2){c->continuous_dirty=0;im_phase_latch(c->phase,0);}
        else if(position_policy(c->current_policy)){
            memcpy(c->position_bank,c->pending_bank,sizeof(c->position_bank));
            c->position_busy=c->pending_busy;
        }
        else if(pipeline_policy(c->current_policy)){uint8_t *p=c->remaining;c->remaining=c->pending_remaining;c->pending_remaining=p;}
        else if(c->current_policy>=4)im_drive_commit_fast(c->remaining,c->commands,c->bytes,c->active_pulses);
        else if(c->current_policy)im_drive_commit(c->remaining,c->commands,c->bytes,c->active_pulses);
        else im_phase_commit(c->levels,c->commands,c->bytes,im_phase_budget(c->phase),c->active_pulses);
        ADD(&c->stats.commit_us,(uint32_t)(micros()-commit_start));
        if(c->pulse_pending==1)ADD(&c->stats.phase_pulses,c->active_pulses);
        c->pulse_pending=0;ADD(&c->stats.phase_scans,1);
        im_phase_heartbeat(c->phase);
    }
    c->head=(c->head+1)%8;c->count--;ADD(&c->stats.completed,1);
    STORE(&c->stats.worker_cpu_us,(uint32_t)process_us());
    return 0;
}
static int drain(im_context *c) {while(c->count)if(wait_oldest(c)<0)return -1;return 0;}
static int end_phase(im_context *c){
    if(im_phase_end(c->phase)<0){STORE(&c->stats.phase_errno,errno);return fail(c);}
    if(c->active_pulses){ADD(&c->stats.phase_restores,1);c->active_pulses=0;}
    c->continuous_dirty=0;
    release_source(c);
    STORE(&c->stats.phase_mode,0);STORE(&c->stats.phase_pending,0);return 0;
}
static void wake_kobo_epdc(void){
    int fd=open("/sys/class/graphics/fb0/power_state",O_WRONLY|O_CLOEXEC);
    if(fd<0)return;
    ssize_t rc;
    do{rc=write(fd,"1,0",3);}while(rc<0&&errno==EINTR);
    close(fd);
}
static int submit(im_context *c,int wave,int full,int x,int y,int w,int h,uint32_t seq) {
    im_config *p=&c->cfg;
    int px=x,py=y,pw=w,ph=h;
    if(p->rotation==1){px=p->physical_width-y-h;py=x;pw=h;ph=w;}
    else if(p->rotation==2){px=p->physical_width-x-w;py=p->physical_height-y-h;}
    else if(p->rotation==3){px=y;py=p->physical_height-x-w;pw=h;ph=w;}
    /* Avoid sub-2-pixel regions rejected by mature mxcfb backends. */
    if(pw<2){if(px>0)px--;pw=2;}if(ph<2){if(py>0)py--;ph=2;}
    ntx_update u={0};u.left=px;u.top=py;u.width=pw;u.height=ph;
    u.wave=wave;u.mode=full;u.marker=0x40000000u+(++c->next_marker);u.temp=4096;
    u.flags=wave==1?2:0;
    uint64_t t=micros();STORE(&c->stats.state,full?CLEAN:SUBMIT);
    int rc=0;
    if(p->fd>=0){
        if(p->wake_epdc)wake_kobo_epdc();
        if(p->transport==IM_KOBO_MK7||p->transport==IM_KINDLE_CARTA){
            v2_update v={.top=u.top,.left=u.left,.width=u.width,.height=u.height,
                .wave=u.wave,.mode=u.mode,.marker=u.marker};
            if(p->transport==IM_KINDLE_CARTA){
                /* Amazon's legacy update inserts the two histogram fields
                 * before temperature and flags. */
                v.fields[0]=1;
                v.fields[1]=u.wave==2?2:3;
                v.fields[2]=4097;
                v.fields[3]=u.flags;
            }else{
                v.fields[0]=4096;
                v.fields[1]=u.flags;
                /* dither_mode/quant_bit zero because the image is binary. */
            }
            do{rc=ioctl(p->fd,SEND_V2,&v);}while(rc<0&&errno==EINTR&&!LOAD(&c->stop));
        }else{
            do{rc=ioctl(p->fd,SEND_NTX,&u);}while(rc<0&&errno==EINTR&&!LOAD(&c->stop));
        }
    }
    uint32_t elapsed=(uint32_t)(micros()-t);
    ADD(&c->stats.send_us,elapsed);if(elapsed>LOAD(&c->stats.max_send_us))STORE(&c->stats.max_send_us,elapsed);
    if(rc<0)return fail(c);
    c->markers[(c->head+c->count)%8]=u.marker;c->count++;
    ADD(&c->stats.requests,1);STORE(&c->stats.last_marker,u.marker);STORE(&c->stats.submitted_seq,seq);
    return 0;
}
static int latest(im_context *c) {
    int chosen=-1,held[3]={0};uint32_t seq=0;
    /* Read metadata only after claiming ownership. The producer may replace
     * READY slots at any moment, including during the candidate scan. */
    for(int i=0;i<3;i++)if(take(&c->slots[i].state,READY,READING)){
        held[i]=1;uint32_t s=c->slots[i].seq;
        if(chosen<0||(int32_t)(s-seq)>0){chosen=i;seq=s;}
    }
    for(int i=0;i<3;i++)if(held[i]&&i!=chosen){STORE(&c->slots[i].state,FREE);ADD(&c->stats.overwritten,1);}
    return chosen;
}
static int worker_run(im_context *c) {
    /* KOReader's subprocess helper uses BATCH/nice 5; restore ordinary policy
     * for an interactive display worker when privileges allow. No RT policy. */
    struct sched_param sp={0};sched_setscheduler(0,SCHED_OTHER,&sp);setpriority(PRIO_PROCESS,0,0);
    prctl(PR_SET_PDEATHSIG,SIGKILL);
    if(getppid()!=c->owner)return -1;
    if(c->cfg.initial_marker&&wait_marker(c,c->cfg.initial_marker)<0)return -1;
    int prepared=0,last_wave=1,known_reference=0;
    uint32_t clean_done=0,reference_pulses=0;
    uint64_t still_since=0;
    while(!LOAD(&c->stop)&&getppid()==c->owner){
        im_phase_heartbeat(c->phase);
        unsigned settings=LOAD(&c->phase_settings);
        if(!LOAD(&c->still)||!fluid_policy(settings>>8)){
            still_since=0;
            STORE(&c->stats.fluid_parked,0);
        }else if(!still_since)still_since=micros();
        int maintenance=c->active_pulses&&fluid_policy(c->current_policy)&&still_since&&
            micros()-still_since>=FLUID_SETTLE_US&&
            LOAD(&c->stats.phase_pulses)-reference_pulses>=FLUID_REBASE_PULSES;
        if(LOAD(&c->stats.fluid_parked))settings&=~255u;
        int requested=LOAD(&c->capture)!=0;
        if(requested!=(int)LOAD(&c->stats.capture_active)){
            if(drain(c)<0)return -1;
            uint32_t scheme=requested?0:2;
            if(c->cfg.fd>=0&&ioctl(c->cfg.fd,0x40044632u,&scheme)<0)return fail(c);
            STORE(&c->stats.capture_active,requested);
        }
        if(LOAD(&c->pause)){
            if(drain(c)<0)return -1;
            if(end_phase(c)<0)return -1;
            fb_copy(c);
            STORE(&c->stats.paused,1);
            while(LOAD(&c->pause)&&!LOAD(&c->stop)&&getppid()==c->owner)usleep(2000);
            STORE(&c->stats.paused,0);prepared=0;known_reference=0;continue;
        }
        /* Bound in-kernel submissions. Wait BEFORE acquiring the newest slot,
         * so a slow waveform does not turn into a backlog of stale images. */
        int ready=-1;
        for(int i=0;i<3;i++)if(LOAD(&c->slots[i].state)==READY){ready=i;break;}
        if(ready<0&&!maintenance&&LOAD(&c->clean)==clean_done&&!LOAD(&c->stats.phase_pending)&&!c->continuous_dirty&&
           (settings&255)==c->active_pulses&&(!c->active_pulses||(settings>>8)==c->current_policy)){
            if(c->cfg.transport!=IM_AURA2&&drain(c)<0)return -1;
            STORE(&c->stats.state,IDLE);
            usleep(1000);
            continue;
        }
        int window=(int)LOAD(&c->queue_window);
        if(window<1)window=1;
        /* Kobo_star 0.4 logs: window 4 exhausted SNAPSHOT resources (ENOMEM).
         * Keep the observed working concurrency bound even for older callers. */
        if(window>2)window=2;
        /* A queued update may capture fb memory later. Without synchronous
         * driver snapshots, reusing that memory before completion is unsafe. */
        if(!LOAD(&c->stats.capture_active))window=1;
        if(c->active_pulses||(settings&255))window=1;
        STORE(&c->stats.effective_window,window);
        /* Pulse mode: quantize the next target in private RAM while the last
         * scan runs. Commands/levels stay untouched until marker completion. */
        if(!c->active_pulses)while(c->count>=(uint32_t)window)if(wait_oldest(c)<0)return -1;
        if(LOAD(&c->stop)||LOAD(&c->pause))continue;
        uint64_t cycle_started=micros();
        unsigned prepared_pending=UINT32_MAX;
        int can_prepare=!maintenance&&c->active_pulses&&pipeline_policy(c->current_policy)&&settings==((c->current_policy<<8)|c->active_pulses)&&
            LOAD(&c->clean)==clean_done&&!LOAD(&c->pause)&&!LOAD(&c->stop);
        int chosen=latest(c),x=0,y=0,w=0,h=0,changed=0,wave=last_wave;uint32_t seq=0;
        if(chosen>=0){
            slot s=c->slots[chosen];c->source_created=s.created_us;wave=s.wave?1:4;seq=s.seq;
            STORE(&c->stats.state,QUANTIZE);uint64_t t=micros();
            if(can_prepare&&position_policy(c->current_policy)){
                prepared_pending=prepare_position(c,pixels(c,chosen),s.dither,s.gamma);
                if(fluid_policy(c->current_policy)){
                    release_source(c);
                    c->retained_source=chosen;
                }
                uint32_t elapsed=(uint32_t)(micros()-t);
                ADD(&c->stats.plan_calls,1);ADD(&c->stats.plan_us,elapsed);
                if(elapsed>LOAD(&c->stats.max_plan_us))STORE(&c->stats.max_plan_us,elapsed);
                if(c->count)ADD(&c->stats.pipelined_plans,1);
            }else if(can_prepare&&c->current_policy>=7){
                const uint8_t *base=c->pulse_pending==1?c->pending_remaining:c->remaining;
                changed=im_quantize_prepare(c,pixels(c,chosen),c->cfg.width,s.dither,s.gamma,c->output,c->targets,base,
                    c->commands,c->prepared_remaining,im_phase_budget(c->phase),c->active_pulses,c->active_pulses<=2?c->alias:0,
                    white_extra(c->current_policy),&prepared_pending);
                uint32_t elapsed=(uint32_t)(micros()-t);
                ADD(&c->stats.fused_calls,1);ADD(&c->stats.fused_us,elapsed);
                ADD(&c->stats.plan_calls,1);ADD(&c->stats.plan_us,elapsed);
                if(elapsed>LOAD(&c->stats.max_plan_us))STORE(&c->stats.max_plan_us,elapsed);
                if(c->count)ADD(&c->stats.pipelined_plans,1);
            }else{
            if(c->active_pulses&&position_policy(c->current_policy)){
                c->position_invalid=1;
                release_source(c);
            }
            changed=c->active_pulses&&c->current_policy>=4?
                im_quantize_target(c,pixels(c,chosen),c->cfg.width,s.dither,s.gamma,c->output):
                im_quantize(c,pixels(c,chosen),c->cfg.width,s.dither,s.gamma,c->output,&x,&y,&w,&h);
            ADD(&c->stats.quant_us,(uint32_t)(micros()-t));
            }
            if(changed<0){errno=EINVAL;return fail(c);}
            ADD(&c->stats.changed,changed);
            ADD(&c->stats.consumed,1);
            if(chosen!=c->retained_source)STORE(&c->slots[chosen].state,FREE);
        }
        /* V4 builds the next transaction while the previous scan is in flight.
         * Its base is the predicted result of that scan. Neither the live
         * framebuffer nor confirmed budgets change before marker completion.
         * Three budget buffers keep confirmed / in-flight / prepared apart. */
        if(can_prepare&&prepared_pending==UINT32_MAX){
            const uint8_t *base=c->pulse_pending==1?c->pending_remaining:c->remaining;
            uint64_t t=micros();
            prepared_pending=position_policy(c->current_policy)?prepare_position(c,NULL,0,0):
                c->current_policy>=7?
                im_drive_prepare_white(c->output,c->targets,base,c->commands,c->prepared_remaining,c->bytes,
                    im_phase_budget(c->phase),c->active_pulses,c->active_pulses<=2?c->alias:0,white_extra(c->current_policy)):
                im_drive_prepare(c->output,c->targets,base,c->commands,c->prepared_remaining,c->bytes,
                    im_phase_budget(c->phase),c->active_pulses,c->active_pulses<=2?c->alias:0);
            uint32_t elapsed=(uint32_t)(micros()-t);ADD(&c->stats.plan_calls,1);ADD(&c->stats.plan_us,elapsed);
            if(elapsed>LOAD(&c->stats.max_plan_us))STORE(&c->stats.max_plan_us,elapsed);
            if(c->count)ADD(&c->stats.pipelined_plans,1);
        }
        if(c->active_pulses)while(c->count>=(uint32_t)window)if(wait_oldest(c)<0)return -1;
        uint32_t clean=LOAD(&c->clean);
        if(clean!=clean_done||(maintenance&&LOAD(&c->still))){
            if(drain(c)<0)return -1;
            /* The retained grayscale frame lets the factory refresh resolve
             * all near-threshold pixels without the motion margin. */
            if(c->retained_source>=0){
                slot s=c->slots[c->retained_source];
                im_quantize_target(c,pixels(c,c->retained_source),c->cfg.width,s.dither,s.gamma,c->output);
            }
            if(end_phase(c)<0)return -1;
            if(LOAD(&c->stop)||LOAD(&c->pause))continue;
            uint64_t t=micros();fb_copy(c);ADD(&c->stats.copy_us,(uint32_t)(micros()-t));
            if(submit(c,2,1,0,0,c->cfg.width,c->cfg.height,seq)<0||drain(c)<0)return -1;
            clean_done=clean;STORE(&c->stats.clean_done,clean);ADD(&c->stats.cleans,1);
            known_reference=1;
            if(maintenance){
                ADD(&c->stats.fluid_refreshes,1);
                STORE(&c->stats.fluid_parked,1);
            }
            prepared=1;last_wave=2;continue;
        }
        settings=LOAD(&c->phase_settings);
        unsigned actual_settings=settings;
        if(LOAD(&c->stats.fluid_parked)&&LOAD(&c->still)&&fluid_policy(settings>>8))settings&=~255u;
        unsigned wanted=settings&255,selected_policy=settings>>8;
        if(wanted!=c->active_pulses||(wanted&&selected_policy!=c->current_policy)){
            int had_phase=c->active_pulses!=0;
            if(drain(c)<0||end_phase(c)<0)return -1;
            if(wanted){
                int allowed=0;
                if((continuous_policy(selected_policy)&&wanted==1&&!single_phase_policy(selected_policy))||
                   (single_phase_policy(selected_policy)&&wanted!=1)){errno=ENOTSUP;allowed=-1;}
                else if(c->cfg.fd<0||c->cfg.width!=758||c->cfg.height!=1024||c->cfg.bpp!=8||c->cfg.rotation||c->cfg.inverse){errno=ENOTSUP;allowed=-1;}
                else allowed=im_phase_preflight(c->phase);
                if(allowed<0){
                    int error=errno;STORE(&c->stats.phase_errno,error?error:ENODEV);take(&c->phase_settings,settings,settings&~255u);
                    /* Preserve this frame for the stock renderer, without
                     * forcing a GC16 for a capability that is unavailable. */
                    wanted=0;
                }
            }
            if(wanted==0&&!had_phase&&LOAD(&c->stats.phase_errno)){
                /* Continue below with the selected stock update, if any. */
            }else{
            /* Establish a known pigment baseline once on entry/exit, never
             * flash while processing pulse scans. Probe while GC16 is active
             * so the EPDC clocks are running when reading its registers. */
            fb_copy(c);
            int reuse=wanted&&fluid_policy(selected_policy)&&known_reference&&!changed&&!had_phase;
            uint64_t prime_start=micros();
            if(submit(c,reuse?1:2,1,0,0,c->cfg.width,c->cfg.height,seq)<0)return -1;
            known_reference=0;
            int probe=0,saved=0;
            if(wanted){
                if(c->cfg.fd<0||c->cfg.width!=758||c->cfg.height!=1024||c->cfg.bpp!=8||c->cfg.rotation||c->cfg.inverse){probe=-1;saved=ENOTSUP;}
                else {probe=im_phase_probe(c->phase);saved=errno;}
            }
            if(drain(c)<0)return -1;
            if(wanted&&probe==0){
                /* Official #5031 epdc_submit_update silently rewrites the
                 * first A2 after GC16 to stock DU unless DU was submitted
                 * explicitly. Prime with the binary baseline BEFORE patching
                 * or arming the short-scan watchdog. Never send drive/HOLD
                 * command gray levels through the factory DU waveform. */
                if(!reuse){
                    prime_start=micros();
                    fb_copy(c);
                    if(submit(c,1,1,0,0,c->cfg.width,c->cfg.height,seq)<0||drain(c)<0)return -1;
                }
                uint32_t prime_time=(uint32_t)(micros()-prime_start);
                ADD(&c->stats.du_primes,1);ADD(&c->stats.du_prime_us,prime_time);
                im_phase_du_primed(c->phase,prime_time);
                if(LOAD(&c->stop)||LOAD(&c->pause)||LOAD(&c->phase_settings)!=actual_settings)continue;
                unsigned continuous=phase_style(selected_policy,wanted);
                if(continuous)probe=im_phase_output(c->phase,c->cfg.framebuffer,(unsigned)c->cfg.stride,(unsigned)c->cfg.width,(unsigned)c->cfg.height);
                if(probe==0)probe=im_phase_begin(c->phase,c->cfg.fd,c->cfg.wait_ioctl,&c->next_marker,wanted,(int)continuous);
                saved=errno;
            }
            if(wanted&&probe<0){
                im_phase_end(c->phase);STORE(&c->stats.phase_errno,saved?saved:ENODEV);take(&c->phase_settings,settings,settings&~255u);
            }else if(wanted){
                unsigned budget=im_phase_budget(c->phase);
                for(size_t i=0;i<c->bytes;i++)c->levels[i]=c->output[i]?(uint8_t)budget:0;
                memcpy(c->targets,c->output,c->bytes);memset(c->remaining,0,c->bytes);
                if(position_policy(selected_policy)){
                    uint8_t endpoint=(uint8_t)position_limit(selected_policy,budget);
                    for(size_t i=0;i<c->bytes;i++)c->remaining[i]=c->output[i]?endpoint:0;
                    memset(c->position_bank,0,sizeof(c->position_bank));
                    c->position_busy=0;
                    c->framebuffer_bands=UINT64_MAX;
                    c->position_invalid=1;
                }
                c->current_policy=selected_policy;c->alias=0;
                reference_pulses=LOAD(&c->stats.phase_pulses);
                c->active_pulses=wanted;STORE(&c->stats.phase_mode,wanted);STORE(&c->stats.phase_errno,0);
            }
            prepared=1;last_wave=2;continue;
            }
        }
        if(c->active_pulses){
            if(LOAD(&c->stop)||LOAD(&c->pause))continue;
            int fast=c->current_policy>=2&&c->active_pulses<=2;
            int continuous=phase_style(c->current_policy,c->active_pulses)!=IM_PHASE_HOLD;
            uint64_t plan_start=micros();
            unsigned pending=prepared_pending!=UINT32_MAX?prepared_pending:position_policy(c->current_policy)?
                prepare_position(c,NULL,0,0):c->current_policy>=7?
                im_drive_prepare_white(c->output,c->targets,c->remaining,c->commands,c->prepared_remaining,c->bytes,im_phase_budget(c->phase),c->active_pulses,fast?c->alias:0,white_extra(c->current_policy)):
                c->current_policy==6?
                im_drive_prepare(c->output,c->targets,c->remaining,c->commands,c->prepared_remaining,c->bytes,im_phase_budget(c->phase),c->active_pulses,fast?c->alias:0):
                c->current_policy>=4?
                im_drive_plan_fast(c->output,c->targets,c->remaining,c->commands,c->bytes,im_phase_budget(c->phase),c->active_pulses,fast?c->alias:0):
                c->current_policy?
                im_drive_plan(c->output,c->targets,c->remaining,c->commands,c->bytes,im_phase_budget(c->phase),c->active_pulses,fast?c->alias:0):
                im_phase_plan(c->output,c->levels,c->commands,c->bytes,im_phase_budget(c->phase),c->active_pulses);
            uint32_t plan_time=(uint32_t)(micros()-plan_start);
            if(prepared_pending==UINT32_MAX){
                ADD(&c->stats.plan_calls,1);ADD(&c->stats.plan_us,plan_time);
                if(plan_time>LOAD(&c->stats.max_plan_us))STORE(&c->stats.max_plan_us,plan_time);
            }
            STORE(&c->stats.phase_pending,pending);
            if(!pending&&(!continuous||!c->continuous_dirty))continue;
            if(continuous&&pending){c->continuous_dirty=1;im_phase_latch(c->phase,1);}
            int scan_top,scan_height;
            position_scan_rows(c,pending,&scan_top,&scan_height);
            uint64_t t=micros();
            if(position_policy(c->current_policy))copy_position_commands(c);
            else fb_copy_from(c,c->commands);
            ADD(&c->stats.copy_us,(uint32_t)(micros()-t));
            /* Rapide alternates equivalent codes in PARTIAL, avoiding FULL
             * snapshot flushes. Comparators/pulse-4 keep FULL for repeated
             * equal commands. Continu sends the all-HOLD ending separately. */
            if(submit(c,4,fast?0:1,0,scan_top,c->cfg.width,scan_height,chosen>=0?seq:LOAD(&c->stats.submitted_seq))<0)return -1;
            if(scan_height<c->cfg.height){
                ADD(&c->stats.region_requests,1);
                ADD(&c->stats.region_rows,(uint32_t)scan_height);
            }
            if(pending&&position_policy(c->current_policy)){
                memcpy(c->pending_bank,c->next_bank,sizeof(c->pending_bank));
                c->pending_busy=c->next_busy;
            }
            else if(pending&&pipeline_policy(c->current_policy)){uint8_t *p=c->pending_remaining;c->pending_remaining=c->prepared_remaining;c->prepared_remaining=p;}
            if(fast)c->alias^=1;
            c->pulse_pending=pending?1:2;last_wave=4;
            ADD(&c->stats.phase_cycles,1);ADD(&c->stats.phase_cycle_us,(uint32_t)(micros()-cycle_started));
            if(pending&&chosen>=0&&seq!=c->last_source_seq){
                c->last_source_seq=seq;ADD(&c->stats.source_updates,1);
                uint64_t age=micros()-c->source_created;
                if(age>LOAD(&c->stats.max_source_age_us))STORE(&c->stats.max_source_age_us,age>UINT32_MAX?UINT32_MAX:(uint32_t)age);
            }
            continue;
        }
        if(chosen<0)continue;
        if(!changed&&prepared)continue;
        if(!prepared){x=y=0;w=c->cfg.width;h=c->cfg.height;wave=1;}
        /* Prepare A2 from a binary DU target once, entirely in the worker. */
        if(last_wave!=4&&wave==4&&drain(c)<0)return -1;
        if(LOAD(&c->stop)||LOAD(&c->pause))continue;
        uint64_t t=micros();fb_copy(c);ADD(&c->stats.copy_us,(uint32_t)(micros()-t));
        if(submit(c,wave,0,x,y,w,h,seq)<0)return -1;
        known_reference=0;
        if(!prepared&&drain(c)<0)return -1;
        prepared=1;last_wave=wave;
    }
    if(drain(c)<0)return -1;
    STORE(&c->stats.state,STOPPED);return 0;
}
int im_run(im_context *c) {
    int result=worker_run(c);
    if(end_phase(c)<0)return -1;
    if(result==0&&c->cfg.transport==IM_AURA2)fb_copy(c);
    if(LOAD(&c->stats.capture_active)){
        uint32_t scheme=2;
        if(c->cfg.fd>=0&&ioctl(c->cfg.fd,0x40044632u,&scheme)<0){fail(c);return -1;}
        STORE(&c->stats.capture_active,0);
    }
    return result;
}
int im_restore_capture(im_context *c) {
    if(!LOAD(&c->stats.capture_active))return 0;
    uint32_t scheme=2;
    if(c->cfg.fd>=0&&ioctl(c->cfg.fd,0x40044632u,&scheme)<0)return -1;
    STORE(&c->stats.capture_active,0);return 0;
}
