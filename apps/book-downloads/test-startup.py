"""Exercise the qBittorrent startup gate without network access or a MAM cookie."""
import datetime
import json
import pathlib
import subprocess
import tempfile
import unittest

IMAGE = 'lscr.io/linuxserver/qbittorrent:5.2.0'
SCRIPT = pathlib.Path(__file__).with_name('wait-for-mam.sh').resolve()


class StartupGate(unittest.TestCase):
    def run_case(self, changes, allowed=False):
        now = datetime.datetime.now(datetime.timezone.utc)
        contact = {'at': (now + datetime.timedelta(seconds=10)).isoformat() + '[UTC]',
                   'reached': True, 'ip': '192.0.2.1',
                   'ipUpdate': {'httpStatus': 200, 'success': True}}
        state = {'hasCookie': True, 'lastMamContact': contact}
        for key, value in changes.items():
            if key == 'hasCookie':
                state[key] = value
            else:
                contact[key] = value
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'public-ip').write_text('192.0.2.1\n')
            (root / 'state.json').write_text(json.dumps(state))
            (root / 'curl').write_text('#!/bin/sh\ncase "$*" in *5010/state*) cat /fixture/state.json;; esac\n')
            (root / 'init').write_text('#!/bin/sh\necho QBITTORRENT_START_ALLOWED\n')
            for filename in ['curl', 'init']:
                (root / filename).chmod(0o755)
            result = subprocess.run([
                'docker', 'run', '--rm', '--network', 'none',
                '--entrypoint', '/bin/sh', '-e', 'MOUSEHOLE_AUTH_TOKEN=test-only',
                '-e', 'PATH=/fixture:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
                '--mount', f'type=bind,src={root},dst=/fixture,readonly',
                '--mount', f'type=bind,src={root},dst=/gluetun,readonly',
                '--mount', f'type=bind,src={root / "init"},dst=/init,readonly',
                '--mount', f'type=bind,src={SCRIPT},dst=/wait-for-mam.sh,readonly',
                IMAGE, '-c', 'timeout 1 /bin/sh /wait-for-mam.sh',
            ], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0 if allowed else 124, result.stderr)
            self.assertEqual('QBITTORRENT_START_ALLOWED' in result.stdout, allowed)

    def test_matching_fresh_success(self):
        self.run_case({}, allowed=True)

    def test_missing_cookie(self):
        self.run_case({'hasCookie': False})

    def test_rejected_cookie(self):
        self.run_case({'ipUpdate': {'httpStatus': 403, 'success': False}})

    def test_rate_limit(self):
        self.run_case({'ipUpdate': {'httpStatus': 429, 'success': False}})

    def test_previous_vpn_ip(self):
        self.run_case({'ip': '192.0.2.2'})

    def test_stale_persisted_state(self):
        self.run_case({'at': '2020-01-01T00:00:00+00:00[UTC]'})

    def test_unreachable(self):
        self.run_case({'reached': False})


if __name__ == '__main__':
    unittest.main()
