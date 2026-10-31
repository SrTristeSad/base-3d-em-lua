#!/usr/bin/env python3
"""Empacota o VoxeLibre completo com o Luanti Windows oficial, sem modificar o jogo."""
from __future__ import annotations

import argparse
import json
import shutil
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


def inspect_game(game_dir: Path) -> None:
    required = ("game.conf", "mods", "LEGAL.md", "LICENSE.txt", "CREDITS.md")
    missing = [name for name in required if not (game_dir / name).exists()]
    if missing:
        raise ValueError("VoxeLibre incompleto; faltam: " + ", ".join(missing))
    if not list((game_dir / "mods").rglob("mod.conf")):
        raise ValueError("Nenhum mod do VoxeLibre encontrado")


def unpack_engine(archive: Path, target: Path) -> Path:
    with zipfile.ZipFile(archive) as zf:
        for member in zf.infolist():
            p = PurePosixPath(member.filename.replace("\\", "/"))
            if p.is_absolute() or ".." in p.parts:
                raise ValueError("Arquivo compactado contém caminho inseguro")
        zf.extractall(target)
    candidates = [
        p for p in target.rglob("*.exe")
        if p.name.lower() in ("luanti.exe", "minetest.exe")
        and p.parent.name.lower() == "bin"
    ]
    if len(candidates) != 1:
        raise ValueError("ZIP do Luanti deve conter um executável principal em bin/")
    return candidates[0].parent.parent


def package(archive: Path, game_dir: Path, out: Path, version: str, revision: str) -> Path:
    inspect_game(game_dir)
    if out.exists():
        raise FileExistsError("Saída já existe: " + str(out))
    with tempfile.TemporaryDirectory() as tmp:
        engine_root = unpack_engine(archive, Path(tmp))
        shutil.copytree(engine_root, out)
    games = out / "games"
    games.mkdir(exist_ok=True)
    if (games / "voxelibre").exists():
        raise ValueError("Pacote Luanti já possui games/voxelibre")
    shutil.copytree(
        game_dir, games / "voxelibre",
        ignore=shutil.ignore_patterns(".git", ".github", "__pycache__", ".DS_Store"),
    )
    inspect_game(games / "voxelibre")
    if not (out / "bin" / "luanti.exe").exists() and not (
        out / "bin" / "minetest.exe"
    ).exists():
        raise ValueError("Motor gráfico ausente no pacote")
    launcher = (
        '@echo off\r\n'
        'cd /d "%~dp0"\r\n'
        'if exist "bin\\luanti.exe" (\r\n'
        '  "bin\\luanti.exe"\r\n'
        ') else (\r\n'
        '  "bin\\minetest.exe"\r\n'
        ')\r\n'
    )
    (out / "JOGAR-VOXELIBRE.bat").write_bytes(launcher.encode("utf-8"))
    instructions = (
        "VOXELIBRE COMPLETO + LUANTI PARA WINDOWS 64-BIT\n\n"
        "1. Extraia todos os arquivos do pacote.\n"
        "2. Execute JOGAR-VOXELIBRE.bat.\n"
        "3. No menu, selecione VoxeLibre, crie um mundo e clique em Jogar.\n"
        "4. Selecione Sobrevivência ou Criativo conforme desejar.\n\n"
        "O pacote inclui o jogo upstream completo, sem remoção de mods.\n"
        "Seus novos mundos são criados nas pastas do Luanti e NÃO migram\n"
        "automaticamente os saves do antigo protótipo LÖVR.\n\n"
        f"Motor: Luanti {version}.\n"
        f"Jogo: VoxeLibre revision {revision}.\n"
        "Codigo e creditos originais em games/voxelibre/.\n"
        "Licencas em games/voxelibre/LEGAL.md e LICENSE.txt.\n"
        "Fontes: https://github.com/VoxeLibre/VoxeLibre e\n"
        "https://github.com/luanti-org/luanti\n"
    )
    (out / "LEIA-ME-PRIMEIRO.txt").write_text(instructions, encoding="utf-8")
    metadata = {
        "engine": "Luanti",
        "engine_version": version,
        "engine_source": "https://github.com/luanti-org/luanti",
        "game": "VoxeLibre",
        "game_revision": revision,
        "game_source": "https://github.com/VoxeLibre/VoxeLibre",
        "game_license": "GPL-3.0-or-later (see LEGAL.md for media licenses)",
    }
    (out / "BUILD_MANIFEST.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--engine-zip", required=True, type=Path)
    ap.add_argument("--game", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--engine-version", required=True)
    ap.add_argument("--game-revision", required=True)
    args = ap.parse_args()
    print(package(args.engine_zip, args.game, args.output,
                  args.engine_version, args.game_revision))


if __name__ == "__main__":
    main()
