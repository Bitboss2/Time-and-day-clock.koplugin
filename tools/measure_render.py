"""Measure deterministic rendering work, never electrical consumption.
Run after tests with PYTHONPATH=testdeps:tests python tools/measure_render.py.
"""
from runtime import Runtime,ROOT
import json

def measure():
    r=Runtime();app=r.app();cls=r.load('render/scene');rows=[]
    for face in app.faces.values():
        scene=cls.new(app,face,app.settings.data,758,1024);scene.render(scene,1793270040)
        initial=scene.draws;areas=[];coarse_areas=[];commands=[];redrawn=0
        for minute in range(1,61):
            previous=scene.draws;scene.render(scene,1793270040+minute*60)
            redrawn+=scene.draws-previous
            areas.append(sum(v.w*v.h for v in scene.regions.values())/(758*1024)*100)
            coarse_areas.append(sum(v.w*v.h for v in scene.coarse_regions.values())/(758*1024)*100)
            commands.append(len(scene.regions))
        rows.append(dict(face=face.id,minutes=60,initial_tiles=initial,redrawn_tiles=redrawn,
                         cold_equivalent_tiles=60*initial,average_requested_area_percent=round(sum(areas)/60,2),
                         maximum_requested_area_percent=round(max(areas),2),
                         average_conservative_area_percent=round(sum(coarse_areas)/60,2),
                         requested_area_reduction_factor=round(sum(coarse_areas)/sum(areas),2) if sum(areas)>0 else None,
                         maximum_commands=max(commands)))
        scene.free(scene)
    r.close()
    data=dict(kind='simulated_render_work_not_battery',screen=[758,1024],notes=[
        'Pillow framebuffer and substitute fonts; electrical energy and native raster speed unmeasured.',
        'Requested windows before controller alignment, KOReader promotion and overlap merging.',
        'Cold equivalent includes rebuilding identical retained tiles; same design, not an older face.',
        'Conservative area is the same face with pre-delta ink bounds, not a battery result.',
        'Excludes initial painting and scheduled full-screen cleanup, which are unchanged.',
        'No change to the number of RTC wakeups at the one-minute setting.'],faces=rows)
    dest=ROOT/'atelierclock.koplugin/docs/RENDER_MEASUREMENTS.json';dest.write_text(json.dumps(data,indent=2)+'\n')
    print(json.dumps(data,indent=2))
if __name__=='__main__':measure()
