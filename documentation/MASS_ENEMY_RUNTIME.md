# Runtime de inimigos: integração, referências e benchmarks

## Estado da entrega

**Atualização 05/09/2026:** [playtest F6 de 5.000 e regras/efeitos do legado](MASS_ENEMY_PLAYTEST_PARITY.md) entregues. O novo benchmark release inclui debris/upgrades e não substitui os registros históricos abaixo. O aceite restante passou a ser 7.3c.

Passos 5, 6.1 e **6.2 (simulação GPU autoritativa)** concluídos. Integração opt-in e medição do nível real em build release verificadas: 10.000 vivos no benchmark isolado, p95 11,18 ms; nível real com 10.000 gerados, pico 9.757 vivos, p95 11,36 ms. Essas medições precedem o perfil de regras e efeitos do legado. Hardware: RTX 4060/Ryzen 5 3600. Os itens 7.3b.1 e 7.3b.2 estão implementados; faltam aceite final, polimento e rollout do passo 7.3c. O contrato atual, capacidades e resultados GPU estão em [Simulação GPU](GPU_ENEMY_SIMULATION.md). As medições CPU abaixo permanecem como referência histórica.

## Testar no editor

Abra `res://src/prototypes/mass_enemies/MassEnemyArena.tscn` e use F6.

- `test_population`: 350 por padrão; teclas 1/2/3/4 reiniciam com 350/1.000/5.000/10.000.
- R reinicia; P pausa/retoma o spawner e a simulação.
- `level_config` fornece roster, quantidade por ponto e intervalo. O total é substituído por `test_population` apenas nesta arena de teste.
- `use_gpu_simulation` ativa simulação GPU autoritativa por padrão na arena. `use_gpu_transforms` escolhe somente o renderizador quando a simulação é CPU. Sem RenderingDevice, o caminho CPU é usado.
- Há 40 pontos, oito barreiras destrutíveis, um planeta e oito emissores aliados sintéticos. A arena não encerra na morte do planeta; contabiliza o dano para inspeção. Não é um benchmark do nível completo.
- Inimigos de um mesmo ponto aparecem exatamente naquele ponto; podem se sobrepor. Não há dispersão aleatória ou separação entre inimigos nesta referência.

Para experimentar no nível real, marque `use_mass_enemies` e mantenha `use_gpu_enemy_simulation = true` no LevelConfig selecionado; recarregue a cena. O Spawner existente encaminha o trabalho ao MassEnemyRuntime. Total, quantidade por ponto, intervalo e roster passam a usar o novo contrato. O primeiro lote só aparece depois do intervalo, não imediatamente. O limite simultâneo do runtime é 10.000; uma onda maior aguarda vagas.

Os LevelConfigs existentes **não foram ativados por padrão**: o backend GPU passou no orçamento medido, mas efeitos/visuais e regras do legado ainda precisam de aceite. O caminho legado continua disponível; não há dois conjuntos de inimigos ativos simultaneamente no modo mass.

## Pipeline da referência CPU e do renderizador de transformações

Este caminho continua selecionável para comparação e fallback inicial sem RenderingDevice. Não é o pipeline autoritativo GPU, descrito no documento acima.

1. `MassEnemySpawner` reserva slots no `EnemyWorld`; não instancia inimigos. Cada slot contém estado individual e handle com geração.
2. `EnemyCombat`, na CPU, avança movimento/estados, monta a grade XZ, consulta ataques e processa projéteis em arrays pré-alocados (4.096 por padrão).
3. `EnemyMultiMeshRenderer` extrai meshes e materiais uma vez por arquétipo, sem inserir a cena visual na árvore. Os modelos atuais produzem oito Nodes de MultiMesh para quatro arquétipos. Hierarquia, escala, overrides de materiais e visibilidade autorada são respeitados; sombras desativadas.
4. No caminho GPU, os arrays compactos de posições e ângulos são enviados diretamente a SSBOs. Listas de slots por arquétipo são reconstruídas somente após spawn/recycle. `enemy_transforms.glsl`, em grupos de 256 threads, combina posição, rotação e transformação local e escreve os 12 floats de cada instância no buffer do MultiMesh.
5. Não há readback de posições no renderizador de produção. **Ainda há upload CPU→GPU por frame**, porque a CPU é dona da simulação. O teste de paridade faz readback explicitamente para verificar resultados, fora do runtime.
6. O bridge aplica eventos agregados a barreiras/planeta, créditos e progresso. Pausa preserva slots; preparação/fim limpam inimigos e projéteis. A última recompensa é entregue antes de abrir o resumo.

Os RIDs próprios são criados/liberados na thread de renderização. O RID do buffer interno do MultiMesh é emprestado e nunca liberado pelo backend. Crescimento realoca os buffers e uniform sets necessários. Falha na criação do shader/pipeline aciona fallback CPU.

O uso de buffers em lote e os limites de culling do MultiMesh seguem a [documentação oficial de MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html). O acesso ao buffer usa [RenderingServer.multimesh_get_buffer_rd_rid](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html). A API compute/SSBO segue o [tutorial oficial de compute shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/compute_shaders.html).

## Combate e limites funcionais

- Asteroides dirigem-se ao planeta, contornam obstáculos por aproximação circular e usam varredura contra retângulos orientados. O retângulo é expandido pelo raio: contato conservador nos cantos. Não usa corpos físicos nem colisão inimigo-inimigo.
- A nave escolhe uma barreira viva, aproxima-se até a distância configurada, para, alinha e atira. Quando perde a barreira, gira e atira no planeta mantendo a posição. Sem barreira disponível, aproxima-se do alcance do planeta e para.
- Targeting usa células e handles; círculo e segmento consideram raio do inimigo. Projétil aliado atinge a primeira interseção; laser atravessa vários inimigos. Tiros inimigos podem ser interceptados por outra barreira antes do planeta.
- Blaster, laser, minas, clique e projéteis de satélite têm conexão ao novo combate. Aliados/UI continuam Nodes. Debris ofensivo e upgrades foram portados ao pool de projéteis, com HP/flash por instância e feedback cosmético limitado. O legado não divide asteroides em novos inimigos; seu burst é debris. Diferenças intencionais e limites estão no mapa de paridade.
- Recompensas ocorrem apenas por morte causada por aliado; impacto no planeta resolve o inimigo sem conceder crédito. Contadores são agregados e um handle reciclado não pode receber dano novamente.
- Na referência CPU, consultas grandes/densas e reconstruções de grade após mortes ainda custam tempo. No backend GPU, movimento/grade/combate são compute; a CPU ainda processa spawn, eventos e reconstrução de membros dos batches. Portanto, custo CPU literalmente zero por inimigo não é uma promessa do sistema.
- AABB fixo cobre X/Z de -4.096 a 4.096 e Y de -512 a 512. Ajustar ou particionar por regiões se o mundo crescer. Um batch não tem culling individual de inimigos.

## Medição reproduzível

`tests/mass_enemy_benchmark.tscn` exige RenderingDevice real e rejeita headless. Executa quatro populações, com transformações CPU/GPU, com/sem simulação CPU. Cada caso tem 30 frames de aquecimento e 120 amostras, VSync desligado, 1.920×1.080.

Distribuição determinística: 60% pequenos, 25% médios, 10% grandes e 5% naves, anel de raio 1.200–1.900, todo dentro da câmera. A fase de combate inclui oito barreiras lógicas e 32 emissores de targeting/tiros a cada seis passos. Usa um passo fixo de 1/60 s por amostra: **não simula a recuperação de múltiplos physics ticks quando um frame real fica lento**. Portanto, carga alta pode ser ainda pior no jogo real. Não inclui todos os VFX/torres visuais do nível.

Saída padrão: `user://mass_enemy_benchmark.json`; argumento opcional `-- --output=caminho.json`. A captura renderizada fica em `user://mass_enemy_10000.png`. Os resultados observados estão em [mass_enemy_benchmark.json](mass_enemy_benchmark.json).

Hardware medido: AMD Ryzen 5 3600, NVIDIA RTX 4060, Godot 4.7.2 Steam, Forward+, D3D12. Executado no binário tools, não em build exportado. O intervalo entre frames apresentou um piso próximo de 11,1 ms; não atribuir esse piso exclusivamente ao custo do jogo ou converter o resultado em promessa de FPS.

`viewport_gpu_median_ms` mede o viewport, não todo o custo do frame nem necessariamente o compute externo ao viewport. `upload_median_ms` mede a preparação/agendamento no script, não uma sincronização de GPU. Draw calls incluem a cena de teste/UI; não equivalem ao número de arquétipos.

### Resultados observados — 04/09/2026

Transformações GPU, tempos em milissegundos:

| Inimigos | Só render, frame mediano | Preparo visual CPU | Viewport GPU | Com combate CPU, frame mediano | Com combate CPU, p95 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 350 | 11,11 | 0,17 | 0,10 | 11,13 | 15,59 |
| 1.000 | 11,11 | 0,19 | 0,12 | 19,54 | 35,55 |
| 5.000 | 11,12 | 0,20 | 0,23 | 87,59 | 161,53 |
| 10.000 | 11,11 | 0,20 | 0,36 | 168,70 | 311,24 |

Todos os casos terminaram com a população esperada, oito Nodes de batches e dez draw calls observados. O caso de 10.000 com combate terminou com 300 projéteis ativos, sem rejeições de tiro. Só render: a referência que empacota as transformações na CPU gastou 35,37 ms de preparo em 10.000; o caminho compute gastou 0,20 ms nessa preparação. A GPU ainda recebe os arrays CPU de estado.

**Decisão histórica da referência CPU:** renderização aceita; combate de 10.000 em GDScript reprovado para 60 FPS. A simulação GPU subsequente resolveu esse gargalo na máquina medida; consultar os novos relatórios antes de comparar. O runner dizer que o benchmark “passed” significa que a coleta terminou, não que atingiu automaticamente um orçamento de performance.

## Verificações

```powershell
.\tests\run_mass_enemy_tests.ps1 -GPU
# Opcional: medição depois da suíte, sem processos Godot concorrentes:
.\tests\run_mass_enemy_tests.ps1 -GPU -Benchmark
# Benchmark do backend autoritativo e do nível completo:
.\tests\run_mass_enemy_tests.ps1 -GPU -GPUCombatBenchmark
```

O runner espera o processo, verifica código de saída, erros de script e marcador de sucesso. Um `--quit-after` com saída zero sozinho não prova sucesso. Logs são gravados em uma pasta temporária própria, sem apagar arquivos do projeto.

- Dados/spawner/World: validações, cadence, capacidade, gerações, 10.000 ativos sem Nodes por inimigo.
- Combate CPU: estados da nave e posição ancorada, planeta, varredura de projéteis, barreira rotacionada, cone, AoE, primeira colisão, crédito único, grade após recycle/spawn com mesma contagem.
- GPU: resultado numérico das transformações comparado à CPU, offsets locais, múltiplos arquétipos, movimento sem reconstruir membros, crescimento de buffers, reciclagem e nenhum slot inativo visível.
- Simulação GPU: trajetórias/estados comparados à referência CPU; renderização não depende de posições CPU; morte oculta antes do ACK; targeting, varredura, HP concorrente, 3.000 mortes excedendo uma página de 2.048, pool de 4.096 tiros cheio e recuperado, gerações e reset de relatórios pendentes.
- Integração: nível GridCombatLevel real, preparação→spawn, pools legados vazios, blaster/laser/minas reais, pausa, reset, créditos e última morte contabilizada antes do resumo.
- Arena: execução renderizada e captura visual; regressões existentes de torres, grid e progressão também executadas.

### Teste legado com falha conhecida

`asteroid_avoidance_test.gd` foi reparado para executar como cena com autoloads e testar os 15 `BasicAllyShip_*` realmente autorados em Level1. O asteroide da fixture de dano agora entra na SceneTree antes de usar posição global. A execução passou dessa falha de infraestrutura, mas **não passou o teste de rotas**: a rota 29 entra em um volume circular de avoidance. As asserções de trajetória não foram relaxadas e o algoritmo legado não foi alterado para esconder o resultado.

O runner deixa esse diagnóstico explícito como aviso e permite reproduzi-lo com `-LegacyAvoidance`. Não faz parte dos quinze testes marcados como aprovados. O combate novo possui testes próprios de movimento/colisões com varredura; eles não demonstram equivalência de todas as rotas do legado. Resolver/aceitar essa diferença faz parte do aceite final, antes de remover compatibilidade.

## Trabalho restante

Seguir 7.3c do [plano](ENEMY_DEVELOPMENT_PLAN.md): legibilidade, rotas/precisão de tiro e testes prolongados no hardware mínimo. Simulação GPU, regras/drop/feedback, playtest e benchmark release já estão entregues. Somente depois do aceite final ativar nos níveis publicados e remover o legado.
