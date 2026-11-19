/* SPDX-License-Identifier: GPL-3.0-or-later
 * Resolve Linux's physical-memory character interface without installing a
 * permanent device node. Merely opening a descriptor performs no memory read.
 */
#define _GNU_SOURCE
#include "mem_access.h"
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>
static void report_access(FILE *report,const char *stage,int error){
 int saved=errno;if(report){fprintf(report,"MEM_ACCESS %s; errno=%d; euid=%lu\n",stage,error,(unsigned long)geteuid());fflush(report);}errno=saved;
}
static int verified_fd(int fd,unsigned kind){
 struct stat st;
 if(fstat(fd,&st)<0)return -1;
 if(!S_ISCHR(st.st_mode)||major(st.st_rdev)!=1||minor(st.st_rdev)!=kind){errno=ENODEV;return -1;}
 return 0;
}
static int open_interface(FILE *report,unsigned kind){
 const int flags=O_RDWR|O_SYNC|O_CLOEXEC|O_NOFOLLOW;
 int fd=open(kind==1?"/dev/mem":"/dev/kmem",flags);
 if(fd>=0){
  if(verified_fd(fd,kind)==0){report_access(report,kind==1?"existing 1:1 interface opened":"existing 1:2 interface opened",0);return fd;}
  int error=errno;close(fd);report_access(report,"existing interface rejected",error);errno=error;return -1;
 }
 int error=errno;
 if(error!=ENOENT){report_access(report,"existing interface open refused",error);errno=error;return -1;}
 report_access(report,kind==1?"pathname absent; trying private temporary 1:1 node":"pathname absent; trying private temporary 1:2 node",ENOENT);
 /* /dev supports device nodes on the target. The onboard FAT filesystem does
  * not. mkdtemp provides a private 0700 directory; its node is owner-only. */
 char directory[]="/dev/.inkmotion-mem-XXXXXX",path[128];
 if(!mkdtemp(directory)){report_access(report,"private directory creation failed",errno);return -1;}
 int count=snprintf(path,sizeof(path),"%s/mem",directory);
 if(count<0||(size_t)count>=sizeof(path)){rmdir(directory);errno=ENAMETOOLONG;return -1;}
 if(mknod(path,S_IFCHR|0600,makedev(1,kind))<0){
  error=errno;rmdir(directory);report_access(report,"private node creation failed",error);errno=error;return -1;
 }
 fd=open(path,flags);error=fd<0?errno:0;
 if(fd>=0&&verified_fd(fd,kind)<0){error=errno;close(fd);fd=-1;}
 /* Unlink immediately, even on open failure. The already opened descriptor
  * remains usable; no /dev/mem or persistent node is left behind. */
 int clean_error=0;
 if(unlink(path)<0)clean_error=errno;
 if(rmdir(directory)<0&&!clean_error)clean_error=errno;
 if(clean_error){if(fd>=0)close(fd);report_access(report,"private node cleanup failed; activation refused",clean_error);errno=clean_error;return -1;}
 if(fd<0){
  report_access(report,error==ENXIO?"kernel does not expose requested memory minor":"private interface open refused",error);errno=error;return -1;
 }
 report_access(report,kind==1?"private 1:1 interface opened; temporary node removed":"private 1:2 interface opened; temporary node removed",0);return fd;
}
int im_open_memory_device(FILE *report){return open_interface(report,1);}
int im_open_kernel_memory_device(FILE *report){return open_interface(report,2);}
