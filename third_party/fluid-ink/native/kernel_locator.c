/* SPDX-License-Identifier: GPL-3.0-or-later
 * Read-only resolver for the published ARM32 Kobo driver. Follow only named
 * EPDC function references to g_fb_data, then validate its waveform fields.
 * No kernel/RAM sweep and no write primitive are provided by this component.
 */
#define _GNU_SOURCE
#include "kernel_locator.h"
#include <errno.h>
#include <string.h>
#define DMA_BYTES 1168216u
#define MAX_DMA_BYTES 1169591u
typedef struct {uint32_t base,lo,hi;im_kernel_reader read;void *opaque;const uint8_t *head;uint32_t physical;int ambiguous;FILE *report;
 unsigned references,global_reads,object_reads,identities,sizes,layouts,prefix_reads,prefix_matches,trace_lines;} locator;
static uint32_t word(const uint8_t *p){return (uint32_t)p[0]|(uint32_t)p[1]<<8|(uint32_t)p[2]<<16|(uint32_t)p[3]<<24;}
static int read_at(locator *s,uint32_t at,void *out,size_t size){
 uint64_t end=(uint64_t)s->base+s->hi-s->lo+1;
 if(at<s->base||(uint64_t)at+size>end)return -1;
 return s->read(s->opaque,at,out,size);
}
static void global_reference(locator *s,uint32_t global){
 uint8_t pointer[4],object[4096];
 s->references++;
 if(read_at(s,global,pointer,4)<0)return;
 s->global_reads++;
 uint32_t address=word(pointer);
 if(address%4||read_at(s,address,object,sizeof(object))<0)return;
 s->object_reads++;
 if(!memmem(object,sizeof(object),"mxc_epdc_fb",11))return;
 s->identities++;
 /* Search only this referenced driver object for the field triplet, and
  * corroborate its preceding temperature/format/mode structure. */
 for(unsigned at=64;at+12<=sizeof(object);at+=4){
  uint32_t bytes=word(object+at+8);
  if(bytes<DMA_BYTES||bytes>MAX_DMA_BYTES)continue;
  s->sizes++;
  uint32_t virt=word(object+at),physical=word(object+at+4);
  if(s->report&&s->trace_lines++<16)fprintf(s->report,"KMEM allocation candidate: object=0x%08x field=%u size=%u virt=0x%08x phys=0x%08x trt=%u ti=%u fmt=0x%x\n",address,at,bytes,virt,physical,word(object+at-64),word(object+at-60),word(object+at-52));
  if(virt<s->base||virt%4||physical%4096||physical<s->lo||(uint64_t)physical+DMA_BYTES>(uint64_t)s->hi+1)continue;
  if(word(object+at-64)!=14||word(object+at-60)>=14||word(object+at-52)!=0x400)continue;
  const uint8_t *modes=object+at-44;
  if(word(modes)!=0||word(modes+4)!=1||word(modes+16)!=2||word(modes+32)!=3||word(modes+36)!=4)continue;
  s->layouts++;
  uint32_t alias=s->base+(physical-s->lo);uint8_t head[64];
  if(read_at(s,alias,head,sizeof(head))<0)continue;
  s->prefix_reads++;
  if(memcmp(head,s->head,sizeof(head)))continue;
  s->prefix_matches++;
  if(s->physical&&s->physical!=physical)s->ambiguous=1;
  s->physical=physical;
 }
}
/* GCC section anchors: a literal can address the start of a data section,
 * followed by LDR [that_register,#4] to fetch g_fb_data. The official #5031
 * EPDC routines use precisely this form; the literal is not the variable. */
static void anchored_references(locator *s,const uint8_t *code,unsigned count,unsigned i,unsigned reg,uint32_t anchor){
 global_reference(s,anchor);
 for(unsigned j=i+1;j<count&&j<=i+3;j++){
  uint32_t op=word(code+4*j);
  if((op>>28)==15)continue;
  if((op&0x0f700000u)==0x05100000u&&((op>>16)&15)==reg){
   uint32_t offset=op&4095u,address=(op&0x00800000u)?anchor+offset:anchor-offset;
   global_reference(s,address);
  }
  /* Stop at an overwrite of this base register for the forms we follow. */
  if(((op>>12)&15)==reg&&(op&0x0c000000u)!=0x08000000u)break;
 }
}
static void function_references(locator *s,uint32_t function,const char *name){
 uint8_t code[256];int error=0;
 if(function%4)error=EINVAL;
 else if(read_at(s,function,code,sizeof(code))<0)error=errno?errno:EIO;
 if(s->report)fprintf(s->report,"KMEM function %s at 0x%08x read_errno=%d\n",name,function,error);
 if(error)return;
 /* Only the first 256 bytes of these named kernel routines are exported,
  * never the contents of candidate objects or arbitrary kernel RAM. */
 if(s->report){fprintf(s->report,"KMEM CODE %s ",name);for(unsigned j=0;j<sizeof(code);j++)fprintf(s->report,"%02x",code[j]);fputc('\n',s->report);}
 uint16_t low[16]={0};int seen[16];for(int i=0;i<16;i++)seen[i]=-100;
 for(unsigned i=0;i<sizeof(code)/4;i++){
  uint32_t op=word(code+4*i);if((op>>28)==15)continue;
  if((op&0x0f7f0000u)==0x051f0000u){
   uint32_t pc=function+4*i+8,offset=op&4095u,at=(op&0x00800000u)?pc+offset:pc-offset;
   uint8_t literal[4];if(read_at(s,at,literal,4)==0)anchored_references(s,code,sizeof(code)/4,i,(op>>12)&15,word(literal));
  }
  unsigned reg=(op>>12)&15,imm=((op>>4)&0xf000)|(op&4095);
  if((op&0x0ff00000u)==0x03000000u){low[reg]=(uint16_t)imm;seen[reg]=(int)i;}
  else if((op&0x0ff00000u)==0x03400000u&&(int)i-seen[reg]<=3){
   anchored_references(s,code,sizeof(code)/4,i,reg,((uint32_t)imm<<16)|low[reg]);seen[reg]=-100;
  }
 }
}
int im_kernel_locate(FILE *symbols,FILE *iomem,im_kernel_reader read,void *opaque,const uint8_t *head,uint32_t *physical,uint32_t *alias,FILE *report){
 if(!symbols||!iomem||!read||!head||!physical||!alias){errno=ENOENT;return -1;}
 char line[512],name[256],type;unsigned long long at,hi;uint32_t text=0,stext=0,global=0,functions[6]={0};
 const char *names[]={"mxc_epdc_fb_set_upd_scheme","mxc_epdc_fb_set_temperature","mxc_epdc_fb_set_waveform_modes","mxc_epdc_get_pwrdown_delay","mxc_epdc_fb_set_pwrdown_delay","mxc_epdc_fb_set_auto_update"};
 while(fgets(line,sizeof(line),symbols)){
  if(sscanf(line,"%llx %c %255s",&at,&type,name)!=3||at>UINT32_MAX||!at)continue;
  if(!strcmp(name,"_text"))text=(uint32_t)at;
  if(!strcmp(name,"_stext"))stext=(uint32_t)at;
  if(!strcmp(name,"g_fb_data"))global=(uint32_t)at;
  for(unsigned i=0;i<6;i++)if(!strcmp(name,names[i])&&(type=='t'||type=='T'))functions[i]=(uint32_t)at;
 }
 locator s={.read=read,.opaque=opaque,.head=head,.report=report};
 while(fgets(line,sizeof(line),iomem))if(sscanf(line," %llx-%llx : %255[^\n]",&at,&hi,name)==3&&!strcmp(name,"System RAM")&&at==0x80000000ull&&hi<=UINT32_MAX&&hi>at){s.lo=(uint32_t)at;s.hi=(uint32_t)hi;break;}
 if(!text)text=stext;
 s.base=text&0xff000000u;
 unsigned found=0;for(unsigned i=0;i<6;i++)found+=functions[i]!=0;
 if(report)fprintf(report,"KMEM metadata: text=0x%08x, EPDC function references=%u, direct global=%u\n",text,found,global!=0);
 if(!s.lo||(s.base!=0x80000000u&&s.base!=0xc0000000u)||text-s.base<0x8000u||text-s.base>=0x100000u){
  if(report)fprintf(report,"KMEM layout refused: _stext/RAM translation unavailable\n");
  errno=ENOTSUP;return -1;
 }
 if(global)global_reference(&s,global);
 for(unsigned i=0;i<6;i++)if(functions[i])function_references(&s,functions[i],names[i]);
 if(report)fprintf(report,"KMEM counters: references=%u global_reads=%u object_reads=%u identities=%u sizes=%u layouts=%u prefix_reads=%u prefix_matches=%u\n",s.references,s.global_reads,s.object_reads,s.identities,s.sizes,s.layouts,s.prefix_reads,s.prefix_matches);
 if(!s.physical||s.ambiguous){
  if(report)fprintf(report,"KMEM driver reference %s; no RAM write\n",s.ambiguous?"ambiguous":"not resolved");
  errno=s.ambiguous?EEXIST:ENOENT;return -1;
 }
 *physical=s.physical;*alias=s.base+s.physical-s.lo;
 if(report)fprintf(report,"KMEM driver reference resolved: ARM32 code/data, fb identity, temperatures, modes, size and waveform prefix verified\n");
 return 0;
}
