/* SPDX-License-Identifier: GPL-3.0-or-later
 * Optional, READ-ONLY collection of the factory waveform for a future driver.
 * No storage scan, register access, kernel writes or LUT installation.
 * The NTX route reads only MBR metadata and the documented fixed waveform slot.
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/prctl.h>
#include <signal.h>
#define LIMIT (16u*1024u*1024u)
#define NTX_WAVE_OFFSET (14336ull*512ull)
static uint32_t read_le32(const uint8_t *p){
 return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static int copy_wave(int fd,uint64_t offset,uint32_t size,int mode,const char *path,FILE *report){
 uint8_t head[48];
 if(size<48||size>LIMIT||pread64(fd,head,48,(off64_t)offset)!=48||head[0x10]!=mode){
  fprintf(report,"Candidate rejected: size/header/mode mismatch\n");return -1;
 }
 int out=open(path,O_WRONLY|O_CREAT|O_EXCL,0600);
 if(out<0){fprintf(report,"Output unavailable: errno=%d\n",errno);return -1;}
 uint8_t buf[65536];uint32_t done=0;int result=0;
 while(done<size){
  size_t amount=size-done;if(amount>sizeof(buf))amount=sizeof(buf);
  ssize_t got=pread64(fd,buf,amount,(off64_t)(offset+done));
  if(got!=(ssize_t)amount){result=-1;break;}
  size_t written=0;
  while(written<amount){ssize_t n=write(out,buf+written,amount-written);if(n<=0){result=-1;break;}written+=(size_t)n;}
  if(result<0)break;
  done+=(uint32_t)amount;
 }
 close(out);
 if(result<0){unlink(path);fprintf(report,"Read/copy failed; partial output removed\n");return -1;}
 fprintf(report,"SUCCESS: %u bytes, factory mode 0x%x, file=%s\n",size,mode,path);return 0;
}
/* NTX hidden-blob layout documented by akemnade/kobo-firmware-extractor:
 * magic[8], little-endian length[4], reserved[4], then payload at sector 14336.
 * Do not scan for candidates or read a mounted partition's contents. Reject
 * absent/ambiguous MBR layouts and any payload that reaches the first partition.
 * This exports a candidate for offline inspection, never for installation. */
static int copy_ntx_wave(int fd,int mode,const char *path,FILE *report){
 static const uint8_t magic[8]={0xff,0xf5,0xaf,0xff,0x78,0x56,0x34,0x12};
 uint8_t mbr[512],head[16];uint64_t first_partition=UINT64_MAX;
 if(pread64(fd,mbr,sizeof(mbr),0)!=(ssize_t)sizeof(mbr)||mbr[510]!=0x55||mbr[511]!=0xaa){
  fprintf(report,"NTX slot rejected: missing MBR signature\n");return -1;
 }
 for(unsigned i=0;i<4;i++){
  const uint8_t *entry=mbr+446+16*i;
  uint32_t start=read_le32(entry+8),length=read_le32(entry+12);
  if(!entry[4]){
   if(start||length){fprintf(report,"NTX slot rejected: ambiguous empty partition entry\n");return -1;}
   continue;
  }
  if(!start||!length){fprintf(report,"NTX slot rejected: invalid partition extent\n");return -1;}
  uint64_t begin=(uint64_t)start*512;
  if(begin<first_partition)first_partition=begin;
 }
 if(first_partition==UINT64_MAX||first_partition<=NTX_WAVE_OFFSET){
  fprintf(report,"NTX slot rejected: not before all declared partitions\n");return -1;
 }
 if(pread64(fd,head,sizeof(head),(off64_t)(NTX_WAVE_OFFSET-sizeof(head)))!=(ssize_t)sizeof(head)||memcmp(head,magic,sizeof(magic))){
  fprintf(report,"NTX slot rejected: fixed-location header absent\n");return -1;
 }
 uint32_t size=read_le32(head+8);
 if(size<48||size>LIMIT||NTX_WAVE_OFFSET+(uint64_t)size>first_partition){
  fprintf(report,"NTX slot rejected: length outside reserved area\n");return -1;
 }
 fprintf(report,"NTX fixed slot validated: sector 14336, length=%u; payload before partitions\n",size);
 return copy_wave(fd,NTX_WAVE_OFFSET,size,mode,path,report);
}
static int collect_waveform(const char *prefix,int kernel_fallback){
 if(!prefix||strlen(prefix)>1800)return -1;
 prctl(PR_SET_PDEATHSIG,SIGKILL);
 char status[2048],output[2048];
 snprintf(status,sizeof(status),"%s-status.txt",prefix);snprintf(output,sizeof(output),"%s-factory-waveform.bin",prefix);
 FILE *report=fopen(status,"w");if(!report)return -1;
 fprintf(report,"Fluid Ink 6.5.0 factory waveform collection; READ ONLY\n");fflush(report);
 FILE *meta=fopen("/sys/class/graphics/fb0/waveform_mode_ver","r");unsigned mode=0;
 if(!meta||fscanf(meta,"%x",&mode)!=1||mode>255){if(meta)fclose(meta);fprintf(report,"Cannot verify current waveform mode; no extraction attempted\n");fclose(report);return -1;}
 fclose(meta);fprintf(report,"Verified current mode: 0x%x\n",mode);
 const char *paths[]={"/lib/firmware/imx/epdc.fw","/lib/firmware/epdc.fw"};
 for(unsigned i=0;i<sizeof(paths)/sizeof(*paths);i++){
  int fd=open(paths[i],O_RDONLY);if(fd<0)continue;
  struct stat st;
  fprintf(report,"File candidate: %s\n",paths[i]);
  int rc=fstat(fd,&st)==0&&S_ISREG(st.st_mode)&&st.st_size>=48&&st.st_size<=(off_t)LIMIT?
      copy_wave(fd,0,(uint32_t)st.st_size,(int)mode,output,report):-1;
  close(fd);if(rc==0){fclose(report);return 0;}
 }
 /* Single known internal device, O_RDONLY, fixed slot only; no discovery or
  * raw-storage sweep. Header, length, reserved-area boundary and mode must pass. */
 int storage=open("/dev/mmcblk0",O_RDONLY|O_CLOEXEC);
 if(storage>=0){
  struct stat st;int rc=-1;
  if(fstat(storage,&st)==0&&S_ISBLK(st.st_mode)){
   fprintf(report,"Read-only NTX fixed-slot candidate: /dev/mmcblk0\n");fflush(report);
   rc=copy_ntx_wave(storage,(int)mode,output,report);
  }else fprintf(report,"NTX route rejected: source is not a block device\n");
  close(storage);if(rc==0){fclose(report);return 0;}
 }else fprintf(report,"NTX internal storage read access unavailable: errno=%d\n",errno);
 if(!kernel_fallback){
  fprintf(report,"No verified file or slot; collection stopped\n");
  fclose(report);
  return -1;
 }
 /* Exact kernel globals only. These can be absent, hidden, or inaccessible.
  * No guesses about physical addresses and no /dev/mem fallback. */
 if(sizeof(void*)!=4){fprintf(report,"Kernel-memory route restricted to ARM32; unavailable here\n");fclose(report);return -1;}
 FILE *symbols=fopen("/proc/kallsyms","r");uint64_t ptr_symbol=0,size_symbol=0;
 if(symbols){
  char line[512],name[256],type;unsigned long long address;
  while(fgets(line,sizeof(line),symbols)){
   if(sscanf(line,"%llx %c %255s",&address,&type,name)!=3)continue;
   if(!strcmp(name,"gpbWF_vaddr"))ptr_symbol=address;
   if(!strcmp(name,"gdwWF_size"))size_symbol=address;
   if(ptr_symbol&&size_symbol)break;
  }
  fclose(symbols);
 }
 if(!ptr_symbol||!size_symbol){fprintf(report,"Exact waveform globals unavailable or hidden; no kernel memory read\n");fclose(report);return -1;}
 int fd=open("/dev/kmem",O_RDONLY);
 if(fd<0){fprintf(report,"/dev/kmem read access unavailable: errno=%d\n",errno);fclose(report);return -1;}
 uint32_t address=0,size=0;
 if(pread64(fd,&address,4,(off64_t)ptr_symbol)!=4||pread64(fd,&size,4,(off64_t)size_symbol)!=4||
    address<0x80000000u||size<48||size>LIMIT||(uint64_t)address+size>0x100000000ull){
  fprintf(report,"Kernel waveform pointers/size failed validation\n");close(fd);fclose(report);return -1;
 }
 fprintf(report,"Exact factory waveform pointer resolved; size=%u\n",size);fflush(report);
 int rc=copy_wave(fd,address,size,(int)mode,output,report);close(fd);fclose(report);return rc;
}
int im_collect_waveform(const char *prefix){return collect_waveform(prefix,1);}
int im_collect_ntx_waveform(const char *prefix){return collect_waveform(prefix,0);}
