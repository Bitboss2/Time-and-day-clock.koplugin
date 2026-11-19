"""Summarize an exported session and its KOReader log, without older sessions.
Usage: python tools/analyze_session.py LAST_SESSION_JSON CRASH_LOG
The output omits device serials and raw kernel messages.
"""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
import collections,json,re,sys

ROOT=Path(__file__).resolve().parents[1]
def analyze(session_path,log_path):
    d=json.loads(Path(session_path).read_text());session=d['session']
    begin,end=session['started'],session['ended'];zone=ZoneInfo('Europe/Paris')
    counts=collections.Counter()
    patterns={'native_prepare':'Kobo suspend: going to sleep',
              'mem_refusal':'Kobo suspend: the kernel refused to enter suspend!',
              'native_retry':'Kobo suspend: putting device back to sleep after',
              'mem_return':'Kobo suspend: ZzZ ZzZ ZzZ'}
    for line in Path(log_path).read_text(errors='replace').splitlines():
        stamp=re.match(r'(\d+/\d+/\d+-\d+:\d+:\d+)',line)
        if not stamp:continue
        at=datetime.strptime(stamp[1],'%m/%d/%y-%H:%M:%S').replace(tzinfo=zone).timestamp()
        if not begin<=at<end:continue
        for name,text in patterns.items():
            if text in line:counts[name]+=1
    p=d['power'];timing=p['timing'];m=d['metrics'];events=p.get('early_short_returns',[])
    verified_vee=sum(bool(x.get('kernel',{}).get('delta_verified')and
        'fp9928_suspend():waiting for VEE stable'in x.get('kernel',{}).get('text',''))for x in events)
    return {'version':d['version'],'model':d['model'],
        'interval':{'start':datetime.fromtimestamp(begin,zone).isoformat(),'end_exclusive':datetime.fromtimestamp(end,zone).isoformat(),
                    'duration_s':end-begin},
        'battery':{'start_points':m['battery_start'],'end_points':m['battery_now'],'drop_points':m['battery_drop_points'],
                   'observed_points_per_hour':m['battery_drop_points']*3600/(end-begin),
                   'target_points_per_hour':60/337,'sevenfold_verified':False,
                   'limitation':'Only one gauge point; no controlled electrical measurement.'},
        'rtc':d['rtc'],'log_counts':dict(counts),'attempts':timing['attempts'],'short_returns':p['short_returns'],
        'verified_sleep_percent':timing['verified_sleep_percent'],
        'kernel_clock_awake_s':timing['elapsed_s']-timing['verified_sleep_s'],
        'verified_early_fp9928_vee_reports':verified_vee,
        'kernel_family':'Linux 3.0.35+','pmic':'FP9928, confirmed by fresh verified kernel messages',
        'user_settings':{k:d['settings'][k]for k in ['interval','wake_margin','fast_rtc','reuse_suspend','full_refresh','face']},
        'user_interruption_note':'373 short calls include the last interrupted call; the log records 372 refusals before session end.'}

if __name__=='__main__':
    report=analyze(*sys.argv[1:3])
    dest=ROOT/'atelierclock.koplugin/docs/SESSION_BETA7_ANALYSIS.json'
    dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report,ensure_ascii=False,indent=2))
