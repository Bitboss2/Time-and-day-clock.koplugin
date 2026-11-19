/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef INKMOTION_H
#define INKMOTION_H
#include <stdint.h>
typedef struct im_context im_context;
enum im_transport { IM_AURA2 = 0, IM_KOBO_NTX, IM_KOBO_MK7, IM_KINDLE_CARTA };
typedef struct {
    int width, height, physical_width, physical_height, stride, bpp, rotation, inverse;
    int fd;
    uint32_t wait_ioctl, initial_marker;
    uint8_t *framebuffer;
    uint32_t transport, wake_epdc;
} im_config;
typedef struct {
    uint32_t published, consumed, overwritten, requests, completed, waits, errors;
    uint32_t changed, quant_us, copy_us, send_us, wait_us, max_send_us;
    uint32_t state, last_errno, submitted_seq, last_marker, cleans, clean_done, paused;
    uint32_t capture_active, effective_window;
    uint32_t phase_mode, phase_errno, phase_pending, phase_scans, phase_pulses, phase_restores;
    uint32_t plan_calls,plan_us,commit_us,max_plan_us,phase_cycles,phase_cycle_us,source_updates,max_source_age_us;
    uint32_t du_primes,du_prime_us;
    uint32_t pipelined_plans;
    uint32_t fused_calls,fused_us;
    uint32_t position_plans,position_pixels,position_cpu_us,worker_cpu_us;
    uint32_t fluid_refreshes,fluid_parked,source_copy_saved;
    uint32_t region_requests,region_rows;
} im_stats;
im_context *im_create(const im_config *config, const uint8_t *noise);
int im_publish(im_context *, const uint8_t *, int stride, int wave, int dither, int gamma, int window);
void im_read_stats(im_context *, im_stats *);
void im_clean(im_context *);
void im_pause(im_context *, int pause);
int im_pause_ack(im_context *);
void im_stop(im_context *);
void im_set_capture(im_context *, int);
int im_configure_phase(im_context *, const char *, const char *);
void im_set_phase(im_context *, unsigned);
void im_set_presentation(im_context *,unsigned policy,unsigned pulses,int retry);
void im_set_still(im_context *,int still);
void im_request_phase(im_context *, unsigned);
void im_set_drive_policy(im_context *,unsigned);
int im_restore_phase(im_context *);
int im_phase_watchdog_tripped(im_context *);
int im_phase_recovery_state(im_context *);
int im_restore_capture(im_context *);
int im_run(im_context *);
void im_destroy(im_context *);
int im_version(void);
unsigned im_abi_size(unsigned which);
/* Same quantizer as the worker; exported for host verification. */
int im_quantize(im_context *, const uint8_t *, int stride, int dither, int gamma,
                uint8_t *, int *x, int *y, int *w, int *h);
int im_quantize_target(im_context *,const uint8_t *,int,int,int,uint8_t *);
int im_quantize_prepare(im_context *,const uint8_t *,int,int,int,uint8_t *,uint8_t *,const uint8_t *,uint8_t *,uint8_t *,unsigned,unsigned,unsigned,unsigned,unsigned *);
int im_quantize_reference(im_context *, const uint8_t *, int, int, int, uint8_t *, int *, int *, int *, int *);
#endif
