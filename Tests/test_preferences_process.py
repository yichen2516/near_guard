"""Fresh-process preference persistence; isolated owned suite, no app lifecycle."""
from pathlib import Path
import json, subprocess, unittest, uuid
ROOT = Path(__file__).resolve().parents[1]
class PreferenceProcessTests(unittest.TestCase):
    def test_true_false_roundtrip_across_fresh_processes(self):
        source = (ROOT/'Sources/NearGuard/main.swift').read_text()
        self.assertIn('runPreferenceProbe', source) # Never launch an old non-probe binary.
        directory = subprocess.check_output(['swift','build','--show-bin-path'], cwd=ROOT,text=True).strip()
        binary = str(Path(directory)/'NearGuard')
        suite = 'NearGuard.PersistenceProbe.' + str(uuid.uuid4())
        results = []
        def run(action):
            result = json.loads(subprocess.check_output([binary,'--preferences-probe',suite,action],cwd=ROOT,text=True))
            results.append({'action': action, 'result': result})
            return result
        try:
            self.assertFalse(run('read')['desiredAutomaticLock'])
            run('true')
            first = run('read'); self.assertTrue(first['desiredAutomaticLock']); self.assertTrue(first['monitoringWanted']); self.assertFalse(first['runtimeGateEnabled'])
            run('false')
            second = run('read'); self.assertFalse(second['desiredAutomaticLock']); self.assertFalse(second['monitoringWanted']); self.assertFalse(second['runtimeGateEnabled'])
        finally:
            cleanup = run('cleanup')
            self.assertFalse(cleanup['desiredAutomaticLock']); self.assertFalse(cleanup['monitoringWanted'])
            (ROOT/'evidence/preferences-process.json').write_text(json.dumps(results,indent=2)+'\n')
if __name__ == '__main__': unittest.main()
