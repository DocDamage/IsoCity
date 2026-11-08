"""Reviewed labels are descriptions layered over stable source identities."""
from pathlib import Path
import copy
import hashlib
import json
import tempfile
import unittest
from unittest import mock
from compile_asset_metadata import ROOT, apply_reviewed_names, compile_metadata


class ReviewedNamesTest(unittest.TestCase):
    def setUp(self):
        out = ROOT / 'output/verification/asset_expansion/I04'
        out.mkdir(parents=True, exist_ok=True)
        self.folder = tempfile.TemporaryDirectory(dir=out)
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        (self.root/'resources/catalog').mkdir(parents=True)
        (self.root/'assets').mkdir()
        (self.root/'assets/picture.png').write_bytes(b'original art')
        self.ident = '2d:opaque_row_02'
        self.source = {'source_name': 'row_02', 'source_pack': 'Fixture', 'directions': {'SE': {'file': '../../picture.png'}}}
        self.entry = {'display_name': "Café owner's table", 'aliases': ['coffee table', 'café furniture'],
                      'source_name': 'row_02', 'source_pack': 'Fixture', 'review_note': 'Synthetic Unicode/apostrophe fixture',
                      'art_sha256': {'assets/picture.png': hashlib.sha256(b'original art').hexdigest()}}

    def apply(self, entry=None, assets=None, sources=None):
        manifest = {'version': 1, 'assets': {self.ident: self.entry if entry is None else entry}}
        (self.root/'resources/catalog/reviewed_names.json').write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
        return apply_reviewed_names(self.root, {self.ident: {}} if assets is None else assets,
                                    {self.ident: self.source} if sources is None else sources)

    def test_unicode_names_keep_source_identity_and_independent_keys(self):
        value = self.apply()[self.ident]
        self.assertEqual("Café owner's table", value['display_name'])
        self.assertEqual('asset.' + self.ident, value['name_key'])
        self.assertEqual('row_02', self.source['source_name'])
        self.assertEqual(['coffee table', 'café furniture'], value['aliases'])

    def test_duplicate_human_names_do_not_merge_ids(self):
        assets = {self.ident: {}, '2d:another': {'display_name': self.entry['display_name']}}
        value = self.apply(assets=assets)
        self.assertEqual(2, len(value))
        self.assertEqual(value[self.ident]['display_name'], value['2d:another']['display_name'])

    def test_invalid_labels_aliases_and_evidence_are_rejected(self):
        for key, values in {'display_name': ['', 2, 'bad\nlabel', 'x'*161],
                            'aliases': ['text', [None], [''], ['table', 'TABLE'], ['bad\talias']],
                            'review_note': ['', None], 'art_sha256': [{}, []]}.items():
            for invalid in values:
                with self.subTest(key=key, invalid=invalid):
                    entry = copy.deepcopy(self.entry); entry[key] = invalid
                    with self.assertRaises(ValueError): self.apply(entry)

    def test_source_changes_and_missing_ids_require_review(self):
        for key in ('source_name', 'source_pack'):
            entry = copy.deepcopy(self.entry); entry[key] += ' changed'
            with self.assertRaises(ValueError): self.apply(entry)
        with self.assertRaises(ValueError): self.apply(sources={})
        (self.root/'assets/picture.png').write_bytes(b'changed art')
        with self.assertRaises(ValueError): self.apply()

    def test_failure_does_not_partially_update_metadata(self):
        assets = {self.ident: {'animation_status': 'static_sprite'}}; before = copy.deepcopy(assets)
        entry = copy.deepcopy(self.entry); entry['art_sha256']['assets/picture.png'] = 'wrong'
        with self.assertRaises(ValueError): self.apply(entry, assets)
        self.assertEqual(before, assets)

    def test_source_view_changes_cannot_keep_stale_names(self):
        source = copy.deepcopy(self.source); source['directions']['SW'] = {'file': '../../other.png'}
        with self.assertRaises(ValueError): self.apply(sources={self.ident: source})

    def test_native_import_provenance_uses_actual_files_without_reclassifying_pack(self):
        source = copy.deepcopy(self.source); source.pop('source_name'); source.pop('source_pack')
        entry = copy.deepcopy(self.entry); entry['source_name'] = None; entry['source_pack'] = None
        result = self.apply(entry, sources={self.ident: source})[self.ident]
        self.assertEqual('res://assets/picture.png', result['name_source'])
        self.assertNotIn('source_name', result)
        self.assertNotIn('source_pack', result)

    def test_invalid_manifest_version_and_shape_are_rejected(self):
        for manifest in [[], None, {'version':True,'assets':{}}, {'version':2,'assets':{}}, {'version':1,'assets':[]}]:
            (self.root/'resources/catalog/reviewed_names.json').write_text(json.dumps(manifest), encoding='utf-8')
            with self.assertRaises(ValueError): apply_reviewed_names(self.root, {}, {})

    def compile_fixture(self):
        self.apply()
        (self.root/'resources/catalog/catalog_registry.json').write_text(json.dumps({'items': {self.ident[3:]: self.source}}), encoding='utf-8')
        compile_metadata(self.root)
        return self.root/'resources/catalog/asset_metadata.json'

    def test_compilation_is_idempotent_and_changed_art_retains_good_metadata(self):
        path = self.compile_fixture(); before = path.read_bytes(); timestamp = path.stat().st_mtime_ns
        compile_metadata(self.root)
        self.assertEqual(before, path.read_bytes())
        self.assertEqual(timestamp, path.stat().st_mtime_ns)
        (self.root/'assets/picture.png').write_bytes(b'changed art')
        with self.assertRaises(ValueError): compile_metadata(self.root)
        self.assertEqual(before, path.read_bytes())

    def test_failed_metadata_replacement_retains_last_good_file(self):
        path = self.compile_fixture(); before = path.read_bytes()
        entry = copy.deepcopy(self.entry); entry['display_name'] = 'Reviewed alternate label'; self.apply(entry)
        with mock.patch('pathlib.Path.replace', side_effect=OSError('simulated failed replacement')):
            with self.assertRaises(OSError): compile_metadata(self.root)
        self.assertEqual(before, path.read_bytes())


if __name__ == '__main__': unittest.main()
