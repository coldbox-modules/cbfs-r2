"""Release verification must not silently replace its published dependency."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


class SDKSelectionTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location('module_runner', Path(__file__).with_name('test.py'))
        self.runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.runner)
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.workspace = self.root / 'run'
        self.workspace.mkdir()

    def manifest(self, version='0.1.0'):
        return {'slug': 'cbfs-r2', 'dependencies': {'r2sdk': version}}

    def source(self, slug='r2sdk'):
        source = self.root / 'r2sdk'
        source.mkdir()
        (source / 'box.json').write_text(json.dumps({'slug': slug}))
        (source / 'ModuleConfig.cfc').write_bytes(b'sdk fixture\n')
        return source

    def test_published_dependency_is_not_replaced_by_a_neighboring_checkout(self):
        self.source()
        self.runner.ROOT = self.root / 'cbfs-r2'
        manifest = self.manifest()
        self.runner.stage_sdk(manifest, self.workspace)
        self.assertEqual(manifest['dependencies']['r2sdk'], '0.1.0')
        self.assertFalse((self.workspace / 'r2sdk').exists())

    def test_folder_dependencies_require_an_explicit_source(self):
        self.source()
        self.runner.ROOT = self.root / 'cbfs-r2'
        with self.assertRaisesRegex(ValueError, 'Supply --sdk-source'):
            self.runner.stage_sdk(self.manifest('../r2sdk/'), self.workspace)

    def test_explicit_source_copies_the_identified_sdk_and_preserves_bytes(self):
        manifest = self.manifest('../r2sdk/')
        self.runner.stage_sdk(manifest, self.workspace, self.source())
        self.assertEqual((self.workspace / 'r2sdk/ModuleConfig.cfc').read_bytes(), b'sdk fixture\n')
        self.assertEqual(manifest['dependencies']['r2sdk'], str(self.workspace / 'r2sdk') + '/')

    def test_refuses_a_different_module_as_the_sdk_override(self):
        with self.assertRaisesRegex(ValueError, 'not r2sdk'):
            self.runner.stage_sdk(self.manifest(), self.workspace, self.source('other'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
