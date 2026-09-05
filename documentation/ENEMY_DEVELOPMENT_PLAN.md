# Plano de desenvolvimento — 10.000 inimigos

Objetivo: suportar 10.000 inimigos visíveis, com comportamento individual baseado em dados. O novo sistema é desenvolvido e testado em paralelo ao jogo atual. Só trocar o runtime principal após validar renderização e combate.

## Lista e estado real

- [x] **1. Dados dos inimigos:** EnemyData, EnemySpawnEntry, quatro arquétipos `.tres`, validação de IDs, referências e pesos. A revisão também passou a rejeitar dados numéricos não finitos e validar os EnemyData referenciados pelo roster.
- [x] **2. LevelConfig:** total da onda, quantidade por ponto/ciclo, intervalo e roster ponderado. Os três configs existentes têm roster válido. `actor_type` está preservado apenas para compatibilidade com o runtime atual. O novo spawner não o consulta. `max_active_enemies` no LevelConfig fica como evolução opcional; hoje a capacidade é configurada no EnemyWorld.
- [x] **3. MassEnemySpawner:** descoberta de pontos ao iniciar, seleção ponderada, limites de ciclos e comandos por frame, tempo acumulado, pausa/retomada, total exato, conclusão única e erros sem falsa conclusão. Configuração é capturada no início da onda. Solicitações confirmadas pelo EnemyWorld; pool cheio mantém pendências.
- [x] **4. EnemyWorld:** arrays pré-alocados, spawn/recycle por slot, handles com geração, eventos agregados, catálogo compartilhado e teste integrado de 10.000 ativos sem Nodes individuais. Cena de teste disponível para F6.
- [x] **5. Protótipo visual:** MultiMeshes por arquétipo/mesh/material, protótipos extraídos fora da SceneTree, hierarquia e escala preservadas. Caminho CPU de referência e compute escrevendo diretamente no buffer nativo das instâncias. Validado em GPU real nas quatro populações, inclusive crescimento, movimento e reciclagem. Resultados em `MASS_ENEMY_RUNTIME.md` e `mass_enemy_benchmark.json`.
- [x] **6. Simulação e combate — referência CPU e backend GPU autoritativo.**
  - [x] **6.1 Referência funcional CPU:** movimento, nave aproximar/atacar barreira/girar/atacar planeta sem sair da posição; grade espacial; dano em círculo/segmento; targeting por handle; projéteis em arrays; recompensas agregadas. Blaster, laser, minas, clique e projéteis dos satélites conectados.
  - [x] **6.2 Simulação compute:** estado persistente, comandos de spawn/dano, movimento/estados, grade, colisões, projéteis, HP atômico e morte única. Readback assíncrono limitado, protegido por geração e época da sessão. Paridade numérica com a referência CPU, overflow de mortes/projéteis, reset e escrita direta no MultiMesh verificados em GPU real.
- [ ] **7. Validação final e troca do runtime — parcial.**
  - [x] **7.1 Integração opt-in:** `LevelConfig.use_mass_enemies`; nível real testado com spawn gradual, torres, pausa, reset, créditos e última morte antes do resumo. Pools antigos de inimigos não são pré-alocados nesse modo. Suíte de regressão preservada.
  - [x] **7.2 Medição inicial:** benchmark renderizado com 350/1.000/5.000/10.000, CPU versus compute de transformações, com/sem simulação CPU; oito barreiras e 32 emissores aliados de targeting/projéteis.
  - [x] **7.3a Integração GPU e benchmark release:** GridCombatLevel com preparação real, 50 pontos, quatro naves aliadas, três blocos e oito torres reais. Testes de pausa, aquisição/dano, créditos, reinício e última recompensa. Build Windows release medido em 5.000/10.000 gerados; teste isolado confirma exatamente 10.000 vivos na GPU. Resultados em `mass_enemy_gpu_release_benchmark.json` e `mass_enemy_gpu_game_release_benchmark.json`.
  - [x] **7.3b.1 Teste jogável de 10.000:** `MassEnemyPlayable5000.tscn` executável por F6, LevelConfig dedicado, preparação e torres do nível real, 50 inimigos por ponto/segundo, regras e feedback ligados. Planeta invulnerável nesse teste. Não altera os níveis publicados.
  - [x] **7.3b.2 Regras e efeitos do legado:** HP aleatório dos asteroides, escalas por zona, desaceleração ao dano, impacto pelo centro, créditos, debris ofensivo e seus upgrades/chance/garantia/piercing. Popups limitados, HP/flash por instância e explosões em MultiMesh fixo. Testes e benchmark com debris efetivamente ativo. Detalhes e diferenças intencionais em `MASS_ENEMY_PLAYTEST_PARITY.md`.
  - [ ] **7.3c Aceite final e rollout:** legibilidade da cena densa, precisão balística com targeting assíncrono, verificação prolongada e hardware mínimo. A fixture de avoidance foi reparada e revelou uma falha preexistente da rota 29 no algoritmo legado; não é teste aprovado. A nave nova mantém o comportamento estacionário pedido, não a órbita antiga. Só retirar compatibilidade após aceitar essas diferenças e o polimento.

**Meta técnica de 10.000 com combate atingida na carga e máquina medidas:** RTX 4060/Ryzen 5 3600, 1080p, D3D12, build release. Teste isolado: 10.000 vivos, p95 11,18 ms. Nível completo: 10.000 gerados, pico de 9.757 vivos após baixas, p95 11,36 ms. Não significa aceite de todos os efeitos nem garantia em outras GPUs. Os LevelConfigs publicados continuam no legado por padrão; o runtime GPU está disponível por opt-in. Nenhum benchmark headless foi usado como prova de renderização.

## Revisão dos passos 2 e 3

O teste inicial passava, mas não exercitava erros no EnemyData interno, pontos criados após o `_ready()` do spawner, pausa por chamada manual, lotes enormes, mudanças de configuração durante a onda ou falta de capacidade no consumidor. Essas situações foram corrigidas e incluídas na suíte antes da implementação do passo 4.

## Arquivos de referência

- [Padrão para assets 3D de inimigos e torres](ASSET_3D_PIPELINE.md)
- [EnemyData e arquétipos](ENEMY_DATA_SYSTEM.md)
- [Contrato do spawner](MASS_ENEMY_SPAWNER.md)
- [EnemyWorld e cena de teste](ENEMY_WORLD.md)
- [Runtime, testes, benchmark e limitações](MASS_ENEMY_RUNTIME.md)
- [Teste jogável de 10.000 e paridade de regras/efeitos](MASS_ENEMY_PLAYTEST_PARITY.md)
- Cena jogável: `res://src/prototypes/mass_enemies/MassEnemyPlayable5000.tscn`
- Cena visual/combatível: `res://src/prototypes/mass_enemies/MassEnemyArena.tscn`
- Cena: `res://src/prototypes/mass_enemies/MassEnemyFoundation.tscn`
- Configuração de teste: `res://src/prototypes/mass_enemies/MassEnemyTestConfig.tres`
- Testes: `enemy_data_validation_test.tscn`, `mass_enemy_spawner_test.tscn`, `enemy_world_test.tscn` em `res://tests/`.

## Aceite do passo 5 (verificado)

1. Renderizar os quatro arquétipos usando os slots ativos do EnemyWorld, sem cenas por inimigo.
2. Verificar spawn/recycle visual e escala dos modelos; não mostrar slots inativos.
3. Usar buffers em lote e grupos apropriados aos meshes/materiais.
4. Medir uma cena real renderizada nas quatro escalas de população; preservar os testes do spawner/World.
5. Atualizar esta lista com resultados observados e limitações.

## Próxima tarefa técnica: 7.3c

1. Revisar o mapa de paridade entregue. O legado não fragmenta asteroides em inimigos menores: seu burst é debris que causa dano. Esse comportamento já está portado, junto dos upgrades e do feedback limitado. Não adicionar novas mecânicas sob o nome de paridade.
2. Dispersão de spawn em disco e separação GPU limitada implementadas e habilitadas no playtest de 10.000. Continuar o ajuste visual em alta densidade; separação suave não garante zero interseções. Reservar posições exclusivas de ataque para naves permanece como evolução separada.
3. Avaliar antecipação de mira/interceptação nas torres. Tiros balísticos miram no snapshot recebido e podem errar asteroides com desvio lateral; não há homing implícito.
4. Repetir medições longas, destruição concentrada, efeitos completos e hardware mínimo definido. Preservar benchmarks de referência sem misturar as cargas.
5. Ativar gradualmente nos LevelConfigs, preservando uma opção de retorno até concluir regressão e aceite visual.
