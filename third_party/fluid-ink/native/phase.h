/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef IM_PHASE_H
#define IM_PHASE_H
#include <stddef.h>
#include <stdint.h>
typedef struct im_phase im_phase;
enum { IM_PHASE_HOLD = 0, IM_PHASE_CONTINUOUS = 1, IM_PHASE_SINGLE_TRIAL = 2 };
im_phase *im_phase_create(const char *reference,const char *report);
int im_phase_preflight(im_phase *p);
/* Probe only while a known stock update has powered the controller. */
int im_phase_probe(im_phase *p);
int im_phase_begin(im_phase *p,int fbfd,uint32_t wait_ioctl,uint32_t *next_marker,unsigned pulses,int continuous);
int im_phase_output(im_phase *,uint8_t *,unsigned,unsigned,unsigned);
void im_phase_heartbeat(im_phase *);
void im_phase_latch(im_phase *,int);
unsigned im_phase_watchdog(im_phase *);
int im_phase_restore_state(im_phase *);
void im_phase_du_primed(im_phase *,unsigned);
int im_phase_end(im_phase *p);
int im_phase_recover(im_phase *p);
void im_phase_destroy(im_phase *p);
unsigned im_phase_budget(im_phase *p);
unsigned im_phase_plan(const uint8_t *target,const uint8_t *level,uint8_t *command,size_t n,unsigned budget,unsigned pulses);
void im_phase_commit(uint8_t *level,const uint8_t *command,size_t n,unsigned budget,unsigned pulses);
unsigned im_drive_plan(const uint8_t *,uint8_t *,uint8_t *,uint8_t *,size_t,unsigned,unsigned,unsigned);
void im_drive_commit(uint8_t *,const uint8_t *,size_t,unsigned);
unsigned im_drive_plan_fast(const uint8_t *,uint8_t *,uint8_t *,uint8_t *,size_t,unsigned,unsigned,unsigned);
void im_drive_commit_fast(uint8_t *,const uint8_t *,size_t,unsigned);
/* Prepare a transaction without spending confirmed budgets. `after` is
 * committed by pointer exchange only after the update marker succeeds. */
unsigned im_drive_prepare(const uint8_t *,uint8_t *,const uint8_t *,uint8_t *,uint8_t *,size_t,unsigned,unsigned,unsigned);
unsigned im_drive_prepare_white(const uint8_t *,uint8_t *,const uint8_t *,uint8_t *,uint8_t *,size_t,unsigned,unsigned,unsigned,unsigned);
#endif
