"""Package the installable plugin, reproducible source and validation evidence."""
from pathlib import Path
import hashlib,json,shutil,zipfile,re

ROOT=Path(__file__).resolve().parents[1]
PLUGIN=ROOT/'atelierclock.koplugin'
VERSION='0.3.1'

def build():
    results=(ROOT/'tests/test-results.txt').read_text()
    match=re.search(r'Ran (\d+) tests',results)
    assert '\nOK\n' in results and match and int(match.group(1))>=168,'Run the complete test suite before packaging'
    version_text=(PLUGIN/'core/version.lua').read_text()
    assert f'"{VERSION}"' in version_text and f'"{VERSION}"'in (PLUGIN/'_meta.lua').read_text(),'version mismatch'
    test_count=int(match.group(1))
    clocks=sorted((PLUGIN/'clocks').glob('*.clock'))
    assert len(clocks)==10
    for path in clocks:
        with zipfile.ZipFile(path) as z:
            assert z.testzip() is None
            assert {'manifest.json','textures/background.png','preview.png'}<=set(z.namelist())
    # Interface screenshots come from tools/build_screenshots.py (real frames).
    for name in ['atelier-galerie.png','atelier-catalogue.png','atelier-composer.png','atelier-modules.png',
                 'atelier-style.png','atelier-options.png','atelier-veille.png','atelier-diagnostic.png','atelier-actions.png']:
        assert (PLUGIN/'docs'/name).is_file(),'run tools/build_screenshots.py first: '+name
    for source,dest in [('collection.png','collection.png'),('landscape-collection.png','collection-paysage.png')]:
        if (ROOT/'tests/output'/source).is_file():shutil.copyfile(ROOT/'tests/output'/source,PLUGIN/'docs'/dest)
        assert (PLUGIN/'docs'/dest).is_file(),dest
    release={'version':VERSION,'date':'2026-11-19',
             'display':{'engine':'Fluid Ink 6.5.0 (ABI 6500), embedded','aura2_v1':{'drive':'Fluid Ink v6','policy':12,'pulses':2,'profile':'Débit (file 1, Bayer 8x8, sans gamma)','target_hz':30},
                        'fallback':'Fluid Ink v6 sans impulsions (policy 12 custom / 2 constructeur, DU au repos)','classic':'UIManager refresh, animations instantanées',
                        'optical_cadence_measured':False,'factory_reference_redistributed':False},
             'rtc_models':{'kobo':['Kobo_star','Kobo_star_r2','Kobo_snow','Kobo_snow_r2','Kobo_alyssum','Kobo_daylight','Kobo_nova'],'kindle_powerd':['KindlePaperWhite2','KindlePaperWhite3','KindleVoyage'],'hardware_tested':False},'preinstalled_clocks':len(clocks),
             'tests':test_count, 'native_rtc_simulated_minutes':90, 'tested_dpi':[167,212,300],'simulated_rtc_cycles':10080,'hardware_tested':False,'weekly_battery_drain':'unmeasured',
             'clock_format':2, 'native_power_simulated_minutes':180, 'power_time_unit':'seconds via ui/time',
             'reuse_suspend_models':['Kobo_star'], 'energy_target':{'factor':7,'maximum_points_per_hour':60/337,'hardware_verified':False},
             'short_return_recovery':{'maximum_retries_per_clock_cycle':2,'guard_delays_s':[1,2],'window_s':12,'retains_native_full_prepare':True},
             'retry_ownership':'private callback argument; native resume cancellation retained',
             'kernel_evidence':{'read_only':True,'maximum_snapshot_bytes':16384,'maximum_automatic_short_snapshots':3,'automatic_exit_report':'settings/atelierclock/last-session.json'},
             'native_integration':{'koreader':'v2026.07.1 Linux SDL3','architectures':['x86_64','armv7 QEMU Cortex-A9 user mode'],'checks_per_run':13,'kobo_kernel_booted':False,'energy_measured':False},
             'vendor_kernel_branches':{'checks':15,'hardware_interactions':'controlled C stubs','kobo_kernel_booted':False},
             'fp9928_rtc_standby':{'activation':'fresh verified VEE refusal, Kobo_star, Linux 3.0.35, native standby available',
                                  'native_state':'standby','duration':'until existing minute alarm','auxiliary_alarms':0,
                                  'native_fallback':True,'session_counters_reset':True,
                                  'user_settings_changed':False,'hardware_energy_verified':False},
             'rtc_standby_simulated_minutes':240,'native_refusal_uses_kernel_flag_not_duration_only':True,
             'user_beta7_session':{'duration_s':11150,'battery_drop_points':1,'rtc_cycles':186,'mem_refusals_in_log':372,
                                  'verified_sleep_percent':80.707539516147,'driver':'FP9928 VEE, confirmed in supplied kernel messages'},
             'user_beta6_log':{'interval':'2026-10-31 09:58 <= timestamp < 12:30','complete_cycles':152,'mem_refusals':227,'guard_wait_s':1380,'cycles_with_15_second_guard':77},
             'user_beta5_observation':{'drop_points':10,'duration_minutes':679,'model':'Kobo_star','render_cpu_ms':23,'requested_area_percent':6.5,'requested_area_factor':1.13,'native_call_percent':67,'direct_reused':1,'fallbacks':1,'source':'user photographs, no control baseline'},
             'delta_refresh':{'maximum_regions':4,'native_buffer':'BB8, no rotation, matching inversion','pixel_scan_limit':1048576},
             'user_battery_observation':{'version':'0.2.0-beta.3','drop_points':7,'duration_minutes':337,'model':'Kobo_star','render_cpu_ms':7,'requested_area_percent':9.3,'native_duration_raw_fts':2787663,'native_duration_s':2.787663,'source':'user photographs, no control baseline'},
             'clock_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in clocks}}
    (PLUGIN/'docs/RELEASE.json').write_text(json.dumps(release,indent=2)+'\n')
    files=list(PLUGIN.rglob('*'))+[ROOT/'DEVELOPPEMENT.md',ROOT/'requirements-test.txt',ROOT/'tests/test-results.txt']
    files+=list((ROOT/'tools').glob('*.py'))+list((ROOT/'tools').glob('*.lua'))+list((ROOT/'tests').glob('*.py'))+list((ROOT/'tests/fixtures').glob('*.clock'))+list((ROOT/'tests/fixtures').glob('*.json'))
    files+=list((ROOT/'validation/beta9').rglob('*'))+list((ROOT/'third_party').rglob('*'))+list((ROOT/'docs').rglob('*'))
    files+=[ROOT/'README.md',ROOT/'CHANGELOG.md',ROOT/'LICENSE']
    files=sorted(set(p for p in files if p.is_file()))
    checksums='\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(ROOT).as_posix() for p in files)+'\n'
    dest=ROOT/'dist'/f'AtelierClock-{VERSION}.zip';dest.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        for p in files:
            info=zipfile.ZipInfo(p.relative_to(ROOT).as_posix(),(2026,11,19,0,0,0));info.compress_type=8;info.external_attr=0o100644<<16
            z.writestr(info,p.read_bytes())
        z.writestr('SHA256SUMS.txt',checksums)
    with zipfile.ZipFile(dest) as z:
        assert z.testzip() is None
        assert len([n for n in z.namelist() if n.startswith('atelierclock.koplugin/clocks/') and n.endswith('.clock')])==10
    print(json.dumps({'file':str(dest),'bytes':dest.stat().st_size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'files':len(files)+1}))

if __name__=='__main__':build()
