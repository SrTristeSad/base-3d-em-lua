# Fase 7 — luz solar por voxel, telhados e entradas de cavernas

**Data:** 31/10/2026. Implementacao original em Lua/LÖVR.

## Recursos

- O teto opaco de cada coluna e encontrado no mundo real, inclusive
  apos mineracao e construcao (`Lighting:skyTop`).
- Poco aberto verticalmente recebe skylight 15 ate o fundo.
- A luz pode entrar lateralmente por galerias, descendo 1 nivel
  por voxel de caminho ate um limite de 14 passos.
- Telhados e paredes bloqueiam a entrada da luz. Remover ou colocar
  blocos invalida as consultas solares e as malhas afetadas.
- Greedy meshing separa faces em seis classes de iluminacao solar,
  mantendo o desenho dinamico de dia/noite sem regenerar geometrias
  a cada tick.
- Cache limitado de colunas e voxels; descarta dados antigos
  durante deslocamentos entre chunks.
- Preserva a Fase 6, o DAYTIME, fornalhas, inventario e saves Classic.

## Limites

Trata-se de um modelo de skylight **aproximado** e nao de um
clone da propagacao original. O caminho por BFS inverso e limitado a
14 passos em regioes sem luz solar direta. Nao ha mistura
fotometrica por vertice, sombras coloridas nem clima.
Precisam ser medidos FPS, consumo de memoria e aparencia em Windows
com Vulkan, especialmente em regioes com galerias numerosas.

## Testes

`lua5.4 tests/beta181_skylight.lua`

O GitHub Actions valida regressao, construcao do pacote LÖVR
e compilacao de Windows x64.
