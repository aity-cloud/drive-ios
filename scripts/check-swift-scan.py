import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name('scan-swift-dependencies.sh').resolve()
for fault in ('none', 'missing-lock', 'missing-pin', 'canceled', 'mr'):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        reports = root / 'vulnerability-reports'
        reports.mkdir()
        (reports / 'scan.complete').touch()
        (reports / 'reports.manifest').write_text(json.dumps([{'file': 'trivy-source.json'}]))
        lock = 'vulnerability-source/build/upstream/ownCloud.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        (reports / 'trivy-source.json').write_text(json.dumps({'Results': [
            {'Target': lock, 'Type': 'swift', 'Packages': [{'Name': 'old'}]},
            {'Target': 'Gemfile.lock', 'Type': 'bundler', 'Packages': [{'Name': 'ruby'}]}]}))
        if fault not in ('missing-lock', 'mr'):
            (root / lock).parent.mkdir(parents=True)
            (root / lock).write_text(json.dumps({'version': 3, 'pins': [
                {'kind': 'remoteSourceControl', 'location': 'https://github.com/johnxnguyen/Down',
                 'state': {'revision': 'a' * 40}},
                {'kind': 'remoteSourceControl', 'location': 'https://github.com/vendor/Versioned.git',
                 'state': {'version': '1.2.3', 'revision': 'b' * 40}}]}))
        scanner = root / 'trivy'
        scanner.write_text('''#!/usr/bin/env python3
import json, os
from pathlib import Path
components = json.loads(Path('vulnerability-reports/swift.cdx.json').read_text())['components']
if os.environ['FAULT'] == 'missing-pin':
    components = components[1:]
packages = [{'Identifier': {'PURL': c['purl']}, 'Version': c['version']} for c in components]
Path('.scan/trivy-swift.json').write_text(json.dumps({'Results': [{'Type': 'swift', 'Packages': packages}]}))
''')
        scanner.chmod(0o755)
        result = subprocess.run(['sh', str(script)], cwd=root, capture_output=True,
                                env={**os.environ, 'PATH': f'{root}:{os.environ["PATH"]}', 'FAULT': fault,
                                     'CI_PIPELINE_SOURCE': 'merge_request_event' if fault == 'mr' else 'push',
                                     'CI_JOB_STATUS': 'canceled' if fault == 'canceled' else 'success'})
        assert (result.returncode == 0) == (fault in ('none', 'mr')), result.stderr
        assert (reports / 'scan.complete').exists() == (fault in ('none', 'mr'))
        if fault == 'none':
            report = json.loads((reports / 'trivy-source.json').read_text())
            swift = [r for r in report['Results'] if r['Type'] == 'swift']
            assert len(swift) == 1 and swift[0]['Target'] == lock
            assert {p['Version'] for p in swift[0]['Packages']} == {'a' * 40, '1.2.3'}
            assert any(r['Type'] == 'bundler' for r in report['Results'])
            receipt = json.loads((reports / 'reports.manifest').read_text())[0]
            assert receipt['sha256'] == hashlib.sha256((reports / 'trivy-source.json').read_bytes()).hexdigest()
print('5 Swift revision coverage, receipt and incomplete-scan checks passed')
