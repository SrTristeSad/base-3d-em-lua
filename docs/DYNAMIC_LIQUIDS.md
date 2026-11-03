# Lote integrado: líquidos dinâmicos no motor Lua

O motor pode simular pares de origem e fluxo (água e lava da demo) de forma **configurável e limitada**, utilizando as propriedades dos NodeDefs do Luanti. Ainda não corresponde ao algoritmo nativo inteiro.

## Implementação

- `Runtime:enableLiquidSimulation({interval=0.5,budget=128})` ativa o simulador; `disableLiquidSimulation()` desativa. O runtime padrão permanece inalterado até o host ativar o recurso.
- `liquidtype`, `liquid_alternative_source`, `liquid_alternative_flowing`, `liquid_range` e `liquid_renewable` orientam o comportamento dos nós registrados.
- A origem de líquido cai e se espalha para os quatro lados. Os três bits inferiores de `param2` representam o nível, e o bit seguinte indica fluxo vertical.
- A propagação evita blocos sólidos, áreas `ignore` não carregadas e líquidos concorrentes. Duas origens adjacentes com apoio podem renovar água. Fluxos sem alimentação desaparecem.
- Uma fila esparsa é reativada pelas alterações dos nós próximos; cada ciclo limita o número de posições processadas. Longos frames têm no máximo quatro ciclos para evitar travamentos.
- Mudanças enviam um `MEET_OTHER` por lote de MapBlocks e o callback `register_on_liquid_transformed`. Os nós usam a mesma persistência `LUAENGINE 1`, sem alteração de formato.
- A demonstração LÖVR registra tipos de água/lava fluindo e ativa o sistema depois de carregar o mapa, com orçamento reduzido.

## Testes

```sh
lua5.4 tests/lua_engine_liquids.lua
luajit tests/lua_engine_liquids.lua
```

## Limites conhecidos

Não há paridade 1:1 com Luanti: mistura/refrigeração de água e lava, pressão, viscosidade temporal, otimizações de grandes volumes, topologia complexa de encostas e algumas reações de nós permanecem pendentes. O trabalho melhora a demo e a base de gameplay, mas não implica VoxeLibre integralmente jogável.
