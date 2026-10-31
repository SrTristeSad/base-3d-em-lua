# Fase 4 — fornalha, combustível e fundição

**Data:** 2026-10-31.

## Implementação

- `src/beta181_furnace.lua`: motor de fundição independente com
  3 slots (entrada, combustível, saída), verificação de receitas,
  consumo de combustível, resultados empilháveis e temporização.
- `src/world.lua`: fornalhas vinculadas a coordenadas de blocos
  ID 51. Salva/recupera cada slot, duração da chama e progresso,
  em linhas `FURNACE` e `FURNACEITEM`. Não converte saves legados.
- `src/beta181_items.lua`: o cursor do inventário interage com
  slots da fornalha. Impede inserir materiais incompatíveis ou
  depositar itens no slot de saída, suporta Shift para retirar
  itens processados.
- `src/ui.lua`: interface própria com espaços de entrada, combustível,
  saída, mochila de 27 slots, barra rápida de nove slots, progresso
  visual do cozimento e indicador de chama.
- `main.lua`: botão direito sobre a fornalha abre a interface; a
  simulação segue funcionando enquanto o mundo estiver ativo,
  inclusive com inventário ou bancada abertos.
- `tests/beta181_furnace.lua`: verifica temporalização, receitas,
  capacidade, retirada, itens, salvamento/restauração e legado.

## Constantes e regras

- Um item leva **200 ticks (10 segundos)** para fundir.
- Um carvão dura **1600 ticks (80 segundos)** e pode processar
  até oito entradas.
- Tronco/tábuas/bancada: **15 segundos**; graveto **5 segundos**.
- Assim que combustível inicia a queima ele é consumido. O tempo
  restante continua diminuindo mesmo após terminar a entrada.
- Combustíveis consecutivos mantêm o progresso de um mesmo item:
  dois gravetos de cinco segundos podem concluir uma fundição.
- O inventário de saída aceita até 64 unidades por pilha.
- Progresso parcial reinicia se o combustível se esgota na
  versão Beta reconstruída, em vez de adotar pausas das
  versões modernas.
- Limite de capacidade/slot impede consumir entrada quando
  saída está cheia.

**Receitas:** minério de ferro → lingote 265, minério de ouro → lingote
266, areia → vidro 16, porco cru 319 → assado 320, bovino cru
363 → bife 364, frango cru 365 → assado 366.

**Atenção aos IDs internos:** no protótipo atual IDs de blocos como
minério de ferro 13 e areia 6 foram mantidos das versões experimentais;
não correspondem aos IDs Mojang.

## Segurança de salvamento e limites

- Ao desmontar uma fornalha com itens, o bloco permanece até
  o jogador esvaziar seus três slots. Isso evita descartar
  itens silenciosamente; não é o comportamento final Beta 1.8.1.
- Não há progresso offline, nem produção em regiões fechadas
  ou outros mundos não ativos.
- Não existem funis/hoppers, lava em baldes, carvão vegetal como
  item distinguível, efeitos de iluminação de fogo nem
  partículas de chamas.
- A geração ainda é uma aproximação; fornalha não torna a
  reprodução historicamente completa.

## Fontes públicas de comportamento

- [Minecraft Wiki — Furnace](https://minecraft.wiki/w/Furnace).
- [Minecraft Wiki — Smelting](https://minecraft.wiki/w/Smelting).

A lógica foi escrita em Lua de forma independente, sem incorporar
código-fonte nem recursos artísticos da Mojang.

## Teste

```sh
lua5.4 tests/beta181_furnace.lua
lua5.4 tests/beta181_survival.lua
lua5.4 tests/beta181_inventory.lua
```

O GitHub Actions valida toda a bateria e empacota versões Windows
e LÖVR. Teste manual da interface e da GPU segue necessário.
