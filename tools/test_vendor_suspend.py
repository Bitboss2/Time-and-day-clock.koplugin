"""Execute unchanged vendor suspend functions with controlled C hardware stubs.

This verifies return/control-flow semantics on the host, not a booted Kobo
kernel, electrical timing, IRQ behavior or battery drain. Nothing accesses
sysfs or hardware. Obtain kernel.tar.bz2 from kobolabs/Kobo-Reader under
hw/imx6sl-auraonetwo and extract it as research-koreader/ntx-kernel first.
The vendor source retains its original GPL license; it is not plugin code.
"""
from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[1]
VENDOR=ROOT/'research-koreader/ntx-kernel'
FILES={
    'drivers/video/mxc/lk_tps65185.c':'fb3610c849d1072447ba983da58ddd9ae063c6025d4cc0eabf8a66ce56de1acb',
    'drivers/video/mxc/mxc_epdc_fb.c':'ce5e0a916e35deb288a1b50134ff81930b27a6917bec018b21b283ed4fce9ad7',
    'drivers/video/mxc/lk_fp9928.c':'e74b2fa53e6070cb1008224be8283870e67d472831beabc5329c19e3f63be7a5',
}

def function(path,signature):
    raw=(VENDOR/path).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==FILES[path],'unexpected vendor source'
    text=raw.decode('latin1');start=text.index(signature)
    end=text.index('\n}',start)+2
    return text[start:end]

STUBS=r'''
#include <stdint.h>
#include <stdio.h>
#define TPS65185_SUSPEND 1
#define EPD_FL_SUSPEND 1
#define EPD_PMIC_SUSPEND 1
#define TPS65185_MODE_SLEEP 1
#define TPS65185_MODE_STANDBY 2
#define POWER_STATE_OFF 0
#define EPD_PMIC_EXCEPTION_STATE_REUPDATING 1
#define KERN_WARNING ""
#define WARNING_MSG(...) ((void)0)
#define DBG_MSG(...) ((void)0)
#define printk(...) ((void)0)
#define dbgENTER() ((void)0)
#define dbgLEAVE() ((void)0)
#define GALLEN_DBGLOCAL_BEGIN() ((void)0)
#define GALLEN_DBGLOCAL_END() ((void)0)
#define GALLEN_DBGLOCAL_RUNLOG(x) ((void)0)
#define GALLEN_DBGLOCAL_ESC() ((void)0)
#define time_before(a,b) ((int32_t)((uint32_t)(a)-(uint32_t)(b))<0)
uint32_t jiffies,gdwSafeTick_To_TurnOFF_EP3V3;
int gSleep_Mode_Suspend=1,pending,fl_bad,exception;
struct {int pwrdwn_work;} gtPwrdwn_work_param;
int delayed_work_pending(void *p){return pending;}
void tps65185_chg_mode(unsigned long *mode,int wait){}
void tps65185_irqs_enable(int enable){}
typedef int pm_message_t;
struct platform_device {int unused;};
struct mxc_epdc_fb_data {int power_state;};
struct mxc_epdc_fb_data data;
struct {struct {int bFrontLight,bDisplayCtrl;} m_val;} hw,*gptHWCFG=&hw;
struct mxc_epdc_fb_data *platform_get_drvdata(void *p){return &data;}
int ntx_epdc_pmic_get_exception_state(void){return exception;}
int FL_suspend(void){return fl_bad?-1:0;}
void mxc_epdc_fb_flush_updates(void *p){}
int fp9928_suspend(void){return 0;}
'''

MAIN=r'''
int main(void){
 struct platform_device p;
 hw.m_val.bDisplayCtrl=6;hw.m_val.bFrontLight=1;
 gdwSafeTick_To_TurnOFF_EP3V3=400;
 jiffies=200;printf("{\"pmic_before_deadline\":%d,",tps65185_suspend());
 printf("\"epdc_before_deadline\":%d,",mxc_epdc_fb_suspend(&p,0));
 jiffies=399;printf("\"epdc_one_tick_before\":%d,",mxc_epdc_fb_suspend(&p,0));
 jiffies=400;printf("\"epdc_at_deadline\":%d,",mxc_epdc_fb_suspend(&p,0));
 pending=1;printf("\"pending_powerdown\":%d,",mxc_epdc_fb_suspend(&p,0));pending=0;
 data.power_state=1;printf("\"epdc_still_powered\":%d,",mxc_epdc_fb_suspend(&p,0));data.power_state=0;
 fl_bad=1;printf("\"frontlight_pending\":%d,",mxc_epdc_fb_suspend(&p,0));fl_bad=0;
 exception=1;printf("\"voltage_recovery\":%d}\n",mxc_epdc_fb_suspend(&p,0));
 return 0;
}
'''

FP_STUBS=r'''
#include <stdint.h>
#include <stdio.h>
#define FP9928_SUSPEND_ENABLED 1
#define FP9928_RET_SUCCESS 0
#define FP9928_RET_NOTINITEDSTATE -1
#define FP9928_RET_PWRDWNWORKPENDING -7
#define WARNING_MSG(...) ((void)0)
#define mutex_lock(p) ((void)0)
#define mutex_unlock(p) ((void)0)
#define time_before(a,b) ((int32_t)((uint32_t)(a)-(uint32_t)(b))<0)
#define GPIO_FP9928_EP_3V3_IN 2
#define GPIO_FP9928_VIN 1
uint32_t jiffies;
int gSleep_Mode_Suspend=1,gpio_calls=0,vin_calls=0;
struct {int tPwrLock,iIsOutputEnabled,iIsEP3V3_SW_enabled;
 uint32_t dwTickEP3V3OffEnd;struct {int pwrdwn_work;}tPwrdwn_work_param;
}fp,*gptFP9928_data=&fp;
int delayed_work_pending(void *p){return 0;}
void _fp9928_vin_onoff(int on){vin_calls++;}
void gpio_direction_output(int pin,int value){gpio_calls++;}
'''
FP_MAIN=r'''
int main(void){
 fp.iIsEP3V3_SW_enabled=1;fp.dwTickEP3V3OffEnd=650;jiffies=100;
 printf("{\"deep_before_discharge\":%d,",fp9928_suspend());
 gSleep_Mode_Suspend=0;vin_calls=0;gpio_calls=0;
 printf("\"shallow_before_discharge\":%d,",fp9928_suspend());
 printf("\"shallow_vin_calls\":%d,\"shallow_ep3v3_calls\":%d,",vin_calls,gpio_calls);
 gSleep_Mode_Suspend=1;jiffies=650;
 printf("\"deep_after_discharge\":%d,",fp9928_suspend());
 printf("\"deep_ep3v3_calls\":%d,",gpio_calls);
 fp.iIsOutputEnabled=1;gSleep_Mode_Suspend=0;
 printf("\"shallow_output_still_enabled\":%d}\n",fp9928_suspend());return 0;
}
'''

def execute(code):
    with tempfile.TemporaryDirectory(prefix='vendor-suspend-',dir=ROOT/'research-koreader')as tmp:
        src=Path(tmp)/'test.c';exe=Path(tmp)/'test';src.write_text(code)
        subprocess.run(['gcc','-std=gnu99','-O0',str(src),'-o',str(exe)],check=True,capture_output=True)
        return json.loads(subprocess.check_output([str(exe)],text=True))

def run():
    code=STUBS+function(next(iter(FILES)),'int tps65185_suspend(void)')
    code+=function('drivers/video/mxc/mxc_epdc_fb.c','static int mxc_epdc_fb_suspend(')+MAIN
    result=execute(code)
    assert result=={'pmic_before_deadline':-2,'epdc_before_deadline':-1,'epdc_one_tick_before':-1,
                   'epdc_at_deadline':0,'pending_powerdown':-1,'epdc_still_powered':-2,
                   'frontlight_pending':-1,'voltage_recovery':-1},result
    fp_result=execute(FP_STUBS+function('drivers/video/mxc/lk_fp9928.c','int fp9928_suspend(void)')+FP_MAIN)
    assert fp_result=={'deep_before_discharge':-7,'shallow_before_discharge':0,'shallow_vin_calls':0,
                      'shallow_ep3v3_calls':0,'deep_after_discharge':0,'deep_ep3v3_calls':1,
                      'shallow_output_still_enabled':-7},fp_result
    report={'status':'passed','cases':result,'fp9928_cases':fp_result,'source_sha256':FILES,'execution':'host C compiler; controlled hardware stubs',
            'kernel_booted':False,'hardware_timing_validated':False,'energy_validated':False,
            'source_url':'https://github.com/kobolabs/Kobo-Reader/tree/master/hw/imx6sl-auraonetwo'}
    dest=ROOT/'atelierclock.koplugin/docs/VENDOR_SUSPEND_TEST.json'
    dest.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))

if __name__=='__main__':run()
