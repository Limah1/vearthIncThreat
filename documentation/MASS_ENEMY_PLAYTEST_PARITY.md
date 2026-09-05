# Playtest de 10.000 e paridade de regras/efeitos

Entrega de 05/09/2026. Corresponde aos dois primeiros blocos solicitados: liberar um teste jogável e portar as regras, drops e feedback do legado. Não representa retirada definitiva do runtime antigo nem polimento visual para 10.000.

## Jogar

Abrir `res://src/prototypes/mass_enemies/MassEnemyPlayable5000.tscn` e executar **F6**. Posicionar aliados/blocos e montar torres pela preparação normal; iniciar a onda pelo botão do nível. É o `GridCombatLevel` real, não a arena sintética.

Configuração editável: `MassEnemyPlayable5000Config.tres`, na mesma pasta:

- `total_enemies = 10000`.
- `enemies_per_spawn_point = 50`.
- `spawn_interval_seconds = 1`.
- Roster 60% pequeno, 25% médio, 10% grande, 5% nave.
- `use_mass_enemies`, `use_gpu_enemy_simulation`, `use_mass_legacy_rules` e `use_mass_enemy_feedback` habilitados.
- `mass_planet_invulnerable = true`: impactos ainda contam e removem inimigos, mas não reduzem o HP do planeta nesta cena de teste.
- `mass_spawn_spread_radius = 250`: cada lote ocupa um disco em espiral ao redor do ponto, com fase diferente por ciclo.
- `mass_gpu_separation = true`, `mass_separation_speed = 120`, `mass_separation_padding = 2`: afastamento GPU gradual com distância desejada igual à soma dos raios mais dois.

Os 50 pontos emitem 2.500 por ciclo global, repartidos em até 1.024 comandos por frame. Primeiro ciclo somente após um segundo; quarto ciclo completa os 10.000, salvo backpressure. O total não é mantido artificialmente após mortes. Os LevelConfigs de campanha e a cena principal do projeto não foram trocados; o config de teste não aparece no seletor público.

O planeta é invulnerável somente neste playtest para permitir sessões longas. Barreiras e aliados continuam recebendo dano normalmente. Desativar `mass_planet_invulnerable` no config restaura dano e derrota pelo planeta.

Dispersão e separação reduzem a sobreposição. O disco não reserva espaço global entre spawn points; com raios grandes ou muita densidade ainda haverá interseções. A separação é suave e limitada a 108 links consultados/12 contatos por inimigo, preserva naves estacionadas e não as empurra através de barreiras. Reservas de posições de ataque não fazem parte desta alteração. Sem RenderingDevice, somente a dispersão permanece ativa. Alterar os parâmetros e recarregar a cena para repetir o teste.

Debris continua dependente da chance/upgrades do jogo. Começar o teste sem desbloqueá-lo mantém chance inicial zero, como no legado. O launcher não concede compras ou dinheiro automaticamente. Recarregar a cena é necessário para alterar backend/perfil de regras, pois os arquétipos são snapshots imutáveis do World.

## Mapa do port

| Comportamento observado no legado | Implementação no runtime mass |
| --- | --- |
| Asteroide nasce com HP inteiro 1–5 | Sorteio por slot no World; HP inicial individual enviado à GPU. Resource original preservado. |
| Velocidade +5% e dano +10% por zona após a primeira | Aplicados à cópia do arquétipo de asteroide no início. |
| Nave: HP e recompensa +12% por zona | Aplicados ao arquétipo sem restaurar a IA orbital antiga. |
| Ao receber dano, asteroide anda a 80% por 0,4 s | Timestamp por slot na GPU e referência CPU; o tick que começa lento permanece lento, inclusive se cruzar a expiração. |
| Asteroide gira em X/Z | Tumble no compute de instâncias e na referência visual CPU. |
| Impacto pelo centro a 45 unidades do planeta | Perfil legado não soma raio do asteroide; varredura evita atravessar o planeta em um tick. |
| Morte aliada concede créditos/progresso; impacto não | Eventos por geração; crédito bancado uma única vez, inclusive na última morte. |
| Morte de asteroide pode criar debris | Evento de morte inclui posição. O bridge faz o roll e emite projéteis de debris, sem Nodes individuais. |
| Debris: 2 + upgrade de quantidade, limitado a 1–16 | Mesmo cálculo, direções originais embaralhadas e perturbação ±0,15. |
| Chance temporária de desbloqueio e reset após sucesso | Usa `GameManager.debris_chance`, reseta para 0,2 + bônus somente no sucesso; garantia consome `b_next_debris_guaranteed` uma vez. |
| Debris: velocidade 240, vida 3 s, dano 3 × multiplicador | Pool de projéteis CPU/GPU; raio 20 contra centros, preservando a regra do debris legado. |
| Piercing causa dano uma vez por alvo | Histórico slot+geração por projétil, até 16 hits. Upgrade atual tem máximo de +3; não repete dano parado dentro de um inimigo nem confunde slots reutilizados. |
| Popup de dano e crédito | Pool existente de 80 Label3D; ponte mass limita solicitações a oito por frame. Dano próximo no tempo pode ser agregado. |
| Feedback visual | HP/flash de dano por cor da instância GPU; explosões/impactos num MultiMesh fixo de 128 anéis. Debris usa esfera laranja de raio visual 8. |

Não existe fragmentação em inimigos menores no AsteroidInstance legado. O burst encontrado no código é debris ofensivo. Não foram adicionados loot coletável ou recompensas extras sob o nome de paridade.

### Diferenças intencionais e limites

- A nave nova aproxima-se da barreira, para, atira e gira para o planeta mantendo posição, conforme pedido. Não volta a orbitar.
- A referência mass usa avoidance simplificado e colisões varridas. Não reproduz exatamente todas as trajetórias do algoritmo antigo nem suas penetrações de volume.
- Crédito é aplicado antes do fim de onda, não por um timer individual de 0,2 s. Isso evita perder a última recompensa. Popups são cosméticos e podem ser suprimidos.
- Debris de mortes GPU começa após o evento assíncrono chegar à CPU. Não há readback de todos os inimigos para antecipá-lo.
- Saturação dos efeitos descarta apenas efeitos. Mortes continuam paginadas sem perda/duplicação de crédito ou de eventos usados pelo sistema de debris. O pool de tiros é limitado a 4.096; sua saturação rejeita tiros e é contabilizada, como uma limitação de gameplay explícita. Comandos rejeitados de debris também têm contador próprio.
- O mapa atual somente tem inimigos mass; aliados/torres/UI permanecem Nodes. Não se afirma paridade de uma onda mista com o sistema legado de lixo espacial.
- O shader permite HP/flash para materiais BaseMaterial3D compatíveis com cor de vértice, sem modificar o material de origem. Shaders customizados precisam consumir a cor da instância para mostrar esse feedback.

## Buffers e orçamento visual

Estado por inimigo continua com 64 bytes. Dois SSBOs adicionais guardam timestamp/dano agregado por inimigo e histórico de hits por projétil. Instâncias autoritativas usam 16 floats, incluindo RGBA. Relatório atual: 78.368 bytes, até 2.048 mortes com posição e 128 registros cosméticos de dano. Com três ticks por relatório e 60 Hz, teto nominal de ~1,57 MB/s de readback.

Feedback de dano pode exceder 128 e ser descartado; isso não descarta mortes. A morte é reconhecida por geração antes de liberar o slot. O teste de 3.000 mortes confirma 3.000 eventos de morte/creditados e descarte apenas dos registros cosméticos excedentes.

## Verificações e benchmark

```powershell
.\tests\run_mass_enemy_tests.ps1 -GPU
.\tests\run_mass_enemy_tests.ps1 -LegacyParityBenchmark
```

Quinze testes no runner, além de importação. Cobrem preparação/config de 10.000, cadastro sem mutar Resources, HP e zona, slowdown/recuperação CPU↔GPU, tumble/flash, piercing e gerações, overflow de tiros/feedback/mortes, pausa/reset, torres e última recompensa. O caso `--legacy-parity` também verifica consumo único do debris garantido e criação de efeito de morte no nível real.

Benchmark: GridCombatLevel, 50 pontos, quatro aliados, três blocos, quatro blasters, dois lasers e dois miners. Perfil/feedback ligados, upgrades de desbloqueio, chance, quantidade e dano de debris em nível 1; piercing em nível 3. São valores da fixture de benchmark, não compras feitas para o jogador. 180 amostras após completar o spawn, ticks normais do engine. RTX 4060/Ryzen 5 3600, 1080p, D3D12, Godot 4.7.2.

| Build release | Pico vivo | Faixa viva nas amostras | Mediana frame | p95 | Bursts de debris |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 5.000 gerados | 4.941 | 4.489–4.941 | 11,967 ms | 13,822 ms | 148 |
| 10.000 gerados | 9.359 | 9.206–9.359 | 11,295 ms | 13,889 ms | 229 |

Sem rejeição de projéteis/comandos de debris nos dois casos. A população não é artificialmente reposta: mortes em cadeia reduzem os vivos. A câmera original não enquadra todos os spawn points. Valores não garantem 10.000 vivos simultâneos com efeitos máximos nem FPS em outro hardware.

Relatórios: [release com debris/upgrades](mass_enemy_legacy_parity_release_benchmark.json), [tools com debris/upgrades](mass_enemy_legacy_parity_upgraded_benchmark.json), [tools sem desbloqueio de debris](mass_enemy_legacy_parity_benchmark.json). O último teve zero bursts e não deve ser apresentado como prova de custo do debris. O piso observado de ~11 ms e a duração curta do teste limitam a interpretação; os tempos novos não devem ser misturados aos benchmarks da etapa anterior.

Exportação release foi feita para pasta temporária própria, sem sobrescrever builds anteriores. Como o template instalado bloqueia scene path pela linha de comando, `override.cfg` ao lado do binário seleciona a cena de teste; a configuração principal do projeto ficou intacta. Para repetir, usar as instruções de exportação em [Simulação GPU](GPU_ENEMY_SIMULATION.md) e acrescentar `--legacy-parity --debris-upgraded` ao benchmark.

### Validação da dispersão e separação

Suíte de quinze cenários passou novamente, incluindo novos casos de distribuição determinística independente do orçamento por frame, snapshot da configuração, pares GPU exatamente coincidentes, delta zero, desligamento do recurso, nave ancorada, bloqueio por barreira e reset. O cálculo de separação não altera o backend de referência CPU; testes de paridade anteriores continuam com a opção desligada.

[Benchmark com dispersão/separação](mass_enemy_separation_benchmark.json): tools/debug, mesma RTX 4060/Ryzen 5 3600, perfil legado, debris com upgrades e planeta invulnerável como no playtest. Para 5.000 gerados: pico 4.849 vivos, p95 15,905 ms. Para 10.000 gerados: pico 7.477 vivos, p95 15,603 ms. As cadeias de debris reduziram os vivos de 7.477 para 729 durante as 180 amostras do segundo caso; não é medição de 10.000 vivos constantes nem comparação isolada do custo do novo pass. Nenhum tiro/comando de debris rejeitado; 2.535 feedbacks cosméticos descartados pelo limite, sem descarte de mortes. A inspeção visual ainda mostra interseções em regiões densas.

Para repetir, executar `mass_enemy_gpu_game_test.tscn` com `-- --benchmark --legacy-parity --debris-upgraded --separation --output=user://mass_enemy_separation_benchmark.json`. A opção `--separation` replica dispersão, separação e invulnerabilidade do playtest. Uma tentativa anterior sem invulnerabilidade terminou por derrota e não serviu para medir a janela completa; o relatório vinculado contém somente a execução concluída.

### Regressão legada não aprovada

O teste `asteroid_avoidance_test.tscn` agora carrega autoloads e os 15 aliados reais de Level1, mas a rota 29 entra num volume circular de avoidance. A asserção não foi removida e o algoritmo não foi alterado. Reproduzir com `-LegacyAvoidance`; esse teste permanece fora dos quinze aprovados. Isso impede declarar equivalência irrestrita de rotas/rollout final, mas não é falha de compilação nem do novo teste jogável.

## Próximo bloco

Polimento de legibilidade, precisão de tiros, rotas e medição prolongada em hardware mínimo (7.3c). Os níveis de campanha continuam opt-in até esse aceite. A presente entrega porta as regras/drop/feedback listados, não declara paridade visual/IA pixel a pixel.
