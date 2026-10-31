# FUTURO — ideias e melhorias para o jogo voxel em Lua

> **Última revisão:** 31/10/2026
>
> **Situação atual:** o repositório ainda possui um protótipo Classic 0.30.
> O próximo objetivo é reconstruir, em Lua + LÖVR, a experiência de jogo
> de **Minecraft Java Beta 1.8.1** com implementação independente.
> Somente depois desse marco começam as melhorias próprias.
>
> **Regra:** o que estiver em "Confirmado" é uma decisão do criador.
> "Em análise" é pesquisa, **não** autorização de implementação nem promessa de lançamento.

## 1. CONFIRMADO — Cubic Chunks

**Primeira grande melhoria após a reconstrução Beta 1.8.1.**

### Objetivo

Substituir o limite vertical rígido do mundo por uma arquitetura capaz de
gerar, simular, renderizar e salvar o terreno por **seções cúbicas 16×16×16**
em uma grade tridimensional, de maneira incremental.

A intenção é explorar grandes profundidades, montanhas enormes,
construções muito altas e diferentes camadas de mundo **sem carregar
toda a coluna vertical na memória**.

### Requisitos de aceitação

- [ ] Manter uma base Beta 1.8.1 funcional e validada para comparação.
- [ ] Gerar seções 16×16×16 independentemente em X, Y e Z.
- [ ] Streaming e descarregamento por distância 3D, incluindo descarte
      de malhas GPU, entidades e dados transitórios.
- [ ] Persistência por coordenadas cúbicas com testes de recarga,
      sem corromper saves, inclusive em alturas negativas e elevadas.
- [ ] Geração determinística de cavernas, estruturas, fluidos e minérios
      cruzando os limites entre seções.
- [ ] Iluminação, céu, colisões, gravidade e regras de spawn que
      funcionem em qualquer faixa vertical suportada.
- [ ] Desempenho medido em FPS, frame time, RAM, geração de chunks e
      tempo de abertura/carregamento.
- [ ] Política de limites numéricos e migração/backups documentada.

**Atenção:** já existe código experimental de seções 16×16×16 no
protótipo Classic, mas o mundo ainda é limitado em altura e isso
**não significa que Cubic Chunks esteja concluído**.

**Risco técnico:** o mod CubicChunks documenta incompatibilidades e
riscos de corrupção, e a geração convencional por colunas requer
reformulações de iluminação, caves, estruturas, minérios e saves.
Nosso motor próprio permite projetar para isso, mas não elimina
a complexidade.

**Fontes:** [projeto CubicChunks (MIT)](https://github.com/OpenCubicChunks/CubicChunks),
[documentação e avisos do mod](https://modrinth.com/mod/cubicchunks),
[discussão de engenharia de geração vertical](https://www.minecraftforum.net/forums/mapping-and-modding-java-edition/minecraft-mods/wip-mods/2792887-cubic-chunks-mod-almost-infinite-world-height-and?page=6).

## 2. REGRAS DEFINIDAS PARA O DESENVOLVIMENTO

- **Primeiro:** referência de comportamento da Beta 1.8.1, incluindo
  inventário, crafting, exploração, sobrevivência, biomas e Nether.
- **Depois:** inovações separadas e testáveis, começando por Cubic Chunks.
- Geração de mundo por **semente determinística**, não por imagem:
  **geração por PNG/JPG foi retirada dos planos futuros**.
- Ideias de jogadores são **insumos de pesquisa**; nenhuma entra sem
  avaliação e escolha do criador.
- Código, arte, áudio, nomes, identidade e outros recursos do produto
  precisam ser próprios ou possuir licença compatível.
- O código legado que aceita imagens ainda existe; sua remoção,
  migração de saves e ajuste do menu são tarefas técnicas futuras,
  não algo já executado.

## 3. PESQUISA DE MERCADO — ONDE HÁ ESPAÇO PARA DIFERENCIAÇÃO

**Pesquisa exploratória em 31/10/2026.** As evidências são pedidos de
usuários, discussões e documentação pública, **não uma pesquisa amostral
representativa nem previsão de vendas**. Em particular, não confundir
recursos desejados com recursos que não existem em nenhuma edição/mod.

### Tamanho da referência e limite da inferência

O Minecraft anunciou ter ultrapassado **300 milhões de cópias vendidas
em outubro de 2023**. Isso demonstra a escala histórica da categoria,
**não** o tamanho do público disposto a comprar nosso jogo nem vendas
anuais de 2026.

Fonte: [Minecraft Live 2023 — anúncio oficial](https://www.minecraft.net/en-us/15th-anniversary).

### Oportunidades observadas

| Tema | Evidência concreta | Oportunidade para um concorrente independente | Limitação ou risco | Situação |
| --- | --- | --- | --- | --- |
| **Construção e exploração vertical** | Pedidos de Cubic Chunks, altura maior e construção de megaprojetos continuam presentes nas sugestões de 2020 e 2026. | Mundo vertical profundo com regiões naturais em diferentes alturas, sem carregar colunas completas. | Muito complexo: iluminação, caves, fluidos, performance e saves. | **Confirmado: Cubic Chunks**; desenho de biomas verticais ainda em análise |
| Organização do inventário | Pedido de ordenação recebeu **186 votos** no Minecraft Feedback; jogadores no Reddit em 2026 ainda discutem caos de baús e mods de ordenação. | Ordenação, busca, filtros e transferência rápida opcionais, preservando o estilo survival. | Pode alterar o ritmo do jogo; testar ergonomia e balanceamento. | **Em análise** |
| Vilas vivas e mutáveis | Pedidos de 2025–2026 sugerem aldeões que construam, ampliem fazendas e reajam ao perigo. | Pequenos assentamentos que cresçam com o tempo e deem novas razões para voltar a regiões exploradas. | IA, navegação, economia e simulação persistente custam CPU e podem desbalancear. | **Em análise** |
| Melhor desempenho e estabilidade | Jogadores pediram otimização de chunks, menos travamentos e maior consistência em 2025–2026. | Projeto leve, opções gráficas reais, carregamento assíncrono e testes em hardware modesto. | Não prometer FPS sem benchmarks reais; LÖVR também possui restrições. | **Critério de qualidade**; funcionalidades específicas em análise |
| Jogar com amigos sem infraestrutura complicada | Feedback de outubro/2026 pede convite direto a mundos Java sem servidor pago; já existe trabalho inicial de lista de amigos, mas nem toda a experiência está resolvida. | Hospedar mundo privado e convidar amigos com fluxo simples, se houver segurança e custo sustentável. | NAT, servidores de retransmissão, segurança, custos e moderação. | **Em análise** |
| Exploração com recompensa e variedade | Discussões em 2026 reclamam de estruturas fáceis, recompensas fracas ou exploração repetitiva; há discordância entre jogadores. | Estruturas e desafios gerados com variação real, motivos para revisitar áreas e progressão não linear. | Repetição procedural e excesso de conteúdo superficial; exige testes de diversão. | **Em análise** |

### Fontes das oportunidades

1. **Verticalidade**
   - [Vertical Cubic Expansion — Minecraft Feedback (2020)](https://feedback.minecraft.net/hc/en-us/community/posts/360059200331-Vertical-Cubic-Expansion)
   - [Java Height Limit — proposta de megaconstruções (setembro/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/49207250235277-Java-Height-Limit)
   - [The world generation and Height Limit — pedido histórico](https://feedback.minecraft.net/hc/en-us/community/posts/360009407571-The-world-generation-and-Height-Limit?page=3)
2. **Inventário**
   - [Inventory Clean Up/Sorting — 186 votos (2018)](https://feedback.minecraft.net/hc/en-us/community/posts/360032471532-Inventory-Clean-Up-Sorting)
   - [How do you sort your items? — r/Minecraft (agosto/2026)](https://www.reddit.com/r/Minecraft/comments/1vdvi15/how_do_you_sort_your_items/)
   - [Debate sobre atualização do inventário — r/Minecraft (setembro/2026)](https://www.reddit.com/r/Minecraft/comments/1wsdlca/question_people_who_want_an_inventory_update_what/)
3. **Vilas e NPCs**
   - [Shouldn't villagers be able to create a village on their own? (novembro/2025)](https://feedback.minecraft.net/hc/en-us/community/posts/41481100464909-Shouldn-t-villagers-be-able-to-create-a-village-on-they-own)
   - [Villagers should have evolving villages (fevereiro/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/43282912298381-Villagers-should-have-evolving-villages)
   - [Villages That Grow and Build Themselves (agosto/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/48362500987405-Villages-That-Grow-and-Build-Themselves)
4. **Desempenho**
   - [Optimization Needed for Low-End Devices (novembro/2025)](https://feedback.minecraft.net/hc/en-us/community/posts/41010609215245-Optimization-Needed-for-Low-End-Devices-Bedrock-Edition)
   - [Please Prioritize Performance and Stability (agosto/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/48014974912013-Please-Prioritize-Performance-and-Stability-on-Minecraft-Bedrock)
   - [Frame Rate Drop in 26.2 (junho/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/46812754716685-Frame-Rate-Drop-in-26-2)
5. **Multijogador**
   - [Simpler Multiplayer (Java edition) — 287 votos (2018)](https://feedback.minecraft.net/hc/en-us/community/posts/360022102912-Simpler-Multiplayer-Java-edition)
   - [Allow Friends to Join Singleplayer Worlds Without Servers (outubro/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/49603304948237-Allow-Friends-to-Join-Singleplayer-Worlds-Without-Servers)
   - [Lista de amigos da Java em desenvolvimento (2026)](https://feedback.minecraft.net/hc/en-us/community/posts/45426155874189-Let-s-talk-about-the-Friends-List-Java)
6. **Exploração**
   - [Debate: Minecraft exploration will always be lacklustre — r/Minecraft (agosto/2026)](https://www.reddit.com/r/Minecraft/comments/1vryf8e/minecraft_exploration_will_always_be_lacklustre/)
   - [Categoria oficial de sugestões de estruturas (agosto/2026)](https://feedback.minecraft.net/hc/en-us/community/posts/48536733480973--Start-Here-About-this-Category-Structures)

## 4. PRIORIZAÇÃO SUGERIDA PARA DEBATE — NÃO APROVADA

A avaliação abaixo combina **valor potencial**, **complexidade** e
**dependências**. Não são números de mercado nem promessas de entrega.

| Candidato | Benefício potencial | Custo técnico relativo | Recomendação para discussão |
| --- | --- | --- | --- |
| Cubic Chunks | Muito alto para exploração e construção | Muito alto | **Já escolhido pelo criador: primeira melhoria** |
| Otimização/estabilidade | Alto para todos os jogadores | Contínuo | Tratar como requisito transversal, não como atualização isolada |
| Ordenação e busca de inventário | Alto no uso diário | Baixo a médio | Bom candidato à primeira melhoria de qualidade de vida após o marco |
| Estruturas exploráveis variadas | Alto para retenção do público survival | Médio a alto | Prototipar com poucas estruturas distintas, medir repetição |
| Aldeias dinâmicas | Alto para sensação de mundo vivo | Alto | Planejar simulação pausada fora da região ativa |
| Convites simples para multiplayer | Alto para grupos de amigos | Muito alto | Só aprovar após análise de segurança e custos de rede |

### Hipótese de posicionamento

Um jogo **survival voxel independente**, com profundidade vertical muito
maior e exploração que faça sentido em cada camada, mantendo bom
desempenho e funcionalidades de conveniência opcionais, pode ocupar
um nicho entre jogadores que gostam de Minecraft mas querem maior
liberdade arquitetônica ou geológica.

**Não existe validação de demanda paga ainda.** Competiremos com um jogo
massivo, muitas atualizações oficiais, mods gratuitos e outros
survivals voxel. Para validar o nicho antes de investir pesado, serão
necessários protótipos jogáveis, testes com jogadores e feedback
sobre retenção, desempenho e disposição a pagar.

## 5. COMO SUGERIR UMA NOVA MELHORIA

Antes de mover uma proposta para "Confirmado", registrar:

- **Problema real:** o que atrapalha a experiência hoje?
- **Público:** quem precisa disso e por quê?
- **Comportamento desejado:** o que muda no jogo?
- **Evidências:** discussões de jogadores, testes e comparação.
- **Custo e riscos:** desempenho, multiplayer, balanceamento e manutenção.
- **Decisão:** proposta, descartada, adiada ou **aprovada pelo criador**.

Este arquivo é um registro de intenções e pesquisa, não uma lista de
tarefas automaticamente autorizadas. Não misturar o desenvolvimento
da Beta 1.8.1 de referência com as futuras melhorias.
