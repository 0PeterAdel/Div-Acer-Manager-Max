"""Exercise fork setup without builds, installation, or lighting writes."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SETUP = Path(__file__).resolve().parents[1] / 'scripts' / 'setup-fork.sh'


class ForkSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.make_repo('app', {
            'scripts/reinstall-damx.sh': '#!/bin/bash\nprintf "DELEGATED:%s:%s\\n" "${1:-install}" "$DAMX_DRIVER_SOURCE"\n',
        })
        self.driver = self.make_repo('driver', {'src/linuwu_sense.c': 'u8 four_zone_static;\n'})
        self.sources = self.root / 'sources'
        self.env = dict(os.environ, DAMX_APP_REPO=str(self.app),
                        DAMX_DRIVER_REPO=str(self.driver), DAMX_SOURCE_DIR=str(self.sources),
                        DAMX_APP_REF='main', DAMX_DRIVER_REF='main')

    def git(self, path, *args):
        return subprocess.check_output(['git', '-C', str(path), *args], text=True,
                                       stderr=subprocess.DEVNULL).strip()

    def make_repo(self, name, files):
        repo = self.root / name
        repo.mkdir()
        self.git(repo, 'init', '-b', 'main')
        self.git(repo, 'config', 'user.email', 'test@example.invalid')
        self.git(repo, 'config', 'user.name', 'Setup test')
        for name, content in files.items():
            path = repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        self.git(repo, 'add', '.')
        self.git(repo, 'commit', '-m', 'Fixture')
        return repo

    def run_setup(self, *args):
        return subprocess.run(['bash', str(SETUP), *args], env=self.env,
                              capture_output=True, text=True)

    def test_clones_main_and_delegates_build_only(self):
        result = self.run_setup('--build-only')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('DELEGATED:--build-only:', result.stdout)
        for name in ('Div-Acer-Manager-Max', 'Div-Linuwu-Sense'):
            self.assertEqual(self.git(self.sources / name, 'branch', '--show-current'), 'main')

    def test_fast_forward_update_on_same_branch(self):
        self.assertEqual(self.run_setup().returncode, 0)
        (self.app / 'new-file').write_text('Update\n')
        self.git(self.app, 'add', 'new-file')
        self.git(self.app, 'commit', '-m', 'Update')
        result = self.run_setup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.sources / 'Div-Acer-Manager-Max', 'rev-parse', 'HEAD'),
                         self.git(self.app, 'rev-parse', 'HEAD'))

    def test_refuses_local_edits_and_preserves_them(self):
        self.assertEqual(self.run_setup().returncode, 0)
        path = self.sources / 'Div-Acer-Manager-Max' / 'scripts/reinstall-damx.sh'
        path.write_text('Local user edit\n')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Local changes found', result.stderr)
        self.assertEqual(path.read_text(), 'Local user edit\n')
        self.assertNotIn('DELEGATED:', result.stdout)

    def test_refuses_branch_switch(self):
        self.assertEqual(self.run_setup().returncode, 0)
        clone = self.sources / 'Div-Acer-Manager-Max'
        self.git(clone, 'checkout', '-b', 'user-work')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(clone, 'branch', '--show-current'), 'user-work')

    def test_refuses_driver_without_static_fix(self):
        path = self.driver / 'src/linuwu_sense.c'
        path.write_text('Original driver\n')
        self.git(self.driver, 'add', '.')
        self.git(self.driver, 'commit', '-m', 'Remove fixture capability')
        result = self.run_setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Merge the complete lighting PRs', result.stderr)
        self.assertNotIn('DELEGATED:', result.stdout)

    def test_help_does_not_clone(self):
        self.assertEqual(self.run_setup('--help').returncode, 0)
        self.assertFalse(self.sources.exists())


if __name__ == '__main__':
    unittest.main()
