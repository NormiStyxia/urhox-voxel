from pathlib import Path
import subprocess,sys
D=Path(__file__).resolve().parent
cases={
 'fixture':'validation/sky-fx/merge-night/fixture_check.py',
 'motion':'validation/sky-fx/motion-visible/check.py',
 'rotation':'validation/sky-fx/rotation_check.py',
 'lua':'validation/sky-fx/check.py',
 'dwp':'validation/sky-fx/missing_dwp_check.py',
 'wind':'validation/sky-fx/wind/check.py',
 'settings-integration':'validation/settings/sky_integration.py',
 'settings-quality':'validation/settings/quality_check.py',
 'settings':'validation/settings/check.py',
 'night':'validation/night-visibility/check.py',
 'night-spatial':'validation/night-visibility/spatial_check.py',
}
failed=False;lines=[]
for name,script in cases.items():
 log=D/(name+'.log')
 with log.open('w') as f:r=subprocess.run([sys.executable,script],stdout=f,stderr=subprocess.STDOUT)
 line=f'python3 {script} — {"FAIL" if r.returncode else "PASS"} — {log}'
 lines.append(line);print(line,flush=True);failed|=bool(r.returncode)
(D/'results.log').write_text('\n'.join(lines)+'\n')
raise SystemExit(int(failed))
