"""Testes de empacotamento sem GPU e sem download de arquivos externos."""
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from package_voxelibre import inspect_game, package, unpack_engine


class PortablePackageTests(unittest.TestCase):
    def test_copy_complete_game_and_engine(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            game = root / "game"
            (game / "mods" / "foo").mkdir(parents=True)
            (game / "game.conf").write_text("title = VoxeLibre\n")
            for name in ("LICENSE.txt", "LEGAL.md", "CREDITS.md"):
                (game / name).write_text(name)
            (game / "mods" / "foo" / "mod.conf").write_text("name = foo")
            (game / "mods" / "foo" / "init.lua").write_text("-- example")
            archive = root / "engine.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                zf.writestr("luanti/bin/luanti.exe", b"dummy exe")
                zf.writestr("luanti/builtin/mainmenu/init.lua", "-- demo")
            out = root / "dist" / "portable"
            package(archive, game, out, "5.18.0", "abc123")
            self.assertTrue((out / "bin" / "luanti.exe").is_file())
            self.assertTrue((out / "builtin" / "mainmenu" / "init.lua").is_file())
            self.assertTrue((out / "games" / "voxelibre" / "mods" / "foo" / "init.lua").is_file())
            self.assertTrue((out / "games" / "voxelibre" / "LEGAL.md").is_file())
            self.assertTrue((out / "JOGAR-VOXELIBRE.bat").is_file())
            metadata = json.loads((out / "BUILD_MANIFEST.json").read_text())
            self.assertEqual(metadata["game_revision"], "abc123")
            with self.assertRaises(FileExistsError):
                package(archive, game, out, "5.18.0", "abc123")

    def test_game_requires_licenses_and_mods(self):
        with tempfile.TemporaryDirectory() as td:
            with self.assertRaises(ValueError):
                inspect_game(Path(td))

    def test_unsafe_zip_paths_blocked(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            archive = root / "unsafe.zip"
            with zipfile.ZipFile(archive, "w") as zf:
                zf.writestr("../unsafe.txt", "bad")
            with self.assertRaises(ValueError):
                unpack_engine(archive, root / "dst")


if __name__ == "__main__":
    unittest.main()
