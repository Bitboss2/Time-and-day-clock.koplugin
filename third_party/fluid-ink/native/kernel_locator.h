/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef IM_KERNEL_LOCATOR_H
#define IM_KERNEL_LOCATOR_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
typedef int (*im_kernel_reader)(void *,uint32_t,void *,size_t);
int im_kernel_locate(FILE *,FILE *,im_kernel_reader,void *,const uint8_t *,uint32_t *,uint32_t *,FILE *);
#endif
