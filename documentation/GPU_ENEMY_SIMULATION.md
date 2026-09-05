# Inimigos GPU — implementação e aceite técnico

## Resultado

**Atualização 05/09/2026:** nível F6 de 5.000 e port das regras/efeitos disponíveis. Ver [playtest e mapa de paridade](MASS_ENEMY_PLAYTEST_PARITY.md). Os benchmarks de 04/09 abaixo são a referência anterior, sem o novo workload de debris/upgrades.

`EnemyGPUCombat` implementa a interface de `EnemyCombat` com simulação autoritativa na GPU. Asteroides e naves são dados individuais no mesmo pool; não são 10.000 Nodes/Actors. O jogo atual mantém planeta, aliados, torres, preparação, UI e progressão, conectados por `MassEnemyRuntime`.

Verificado em 04/09/2026: Godot 4.7.2, Windows, Forward+, D3D12, RTX 4060, Ryzen 5 3600, 1.920×1.080. Build Windows release exportado pelo preset existente. Não há promessa de performance para outros hardwares ou efeitos ainda não portados.

## Como usar

1. No LevelConfig selecionado, habilitar `use_mass_enemies` e `use_gpu_enemy_simulation`.
2. Configurar `total_enemies`, `enemies_per_spawn_point`, `spawn_interval_seconds` e `enemy_roster`.
3. Recarregar o nível e iniciar a onda pela preparação normal. Não adicionar a arena ao nível: o Spawner cria o bridge automaticamente.

Exemplo com os 50 pontos do primeiro nível: `total_enemies = 5000`, `enemies_per_spawn_point = 50`, `spawn_interval_seconds = 1`. Cada ponto emite até 50 por ciclo, respeitando o total compartilhado da onda. O lote global é repartido por um limite de 1.024 comandos por frame; não são 2.500 instâncias criadas no mesmo frame. Total da onda não significa quantidade de vivos: mortes liberam vagas, mas não geram reposições além do total configurado.

Para teste isolado, executar `MassEnemyArena.tscn` com F6; tecla 3 seleciona 5.000 e tecla 4 seleciona 10.000. A arena tem combate GPU por padrão, começa em 350 e preserva os controles R/P. Níveis publicados mantêm `use_mass_enemies = false` até o aceite final.

## Ownership e pipeline

- CPU: configurações, reserva de slots/gerações, comandos, torres/aliados e aplicação de eventos agregados ao jogo.
- GPU: posição, velocidade, orientação, HP, estado individual, timer/alvo da nave, grade, colisões e pool de projéteis.
- `EnemyWorld.positions/health/states`: snapshots apenas dos alvos consultados; não percorrer esses arrays esperando o estado atual de todos os inimigos. Spawn/recycle seguem pelo journal ordenado `gpu_changes`.

`EnemyGPUBackend` usa o RenderingDevice principal exclusivamente na thread de renderização. Buffers são persistentes, com structs alinhadas a 16 bytes e stride de 64 bytes por inimigo. Push constant de simulação: 80 bytes; render permanece com 64. `enemy_sim.glsl` usa grupos de 256 threads e barreiras entre passes:

1. Aplicar comandos de alocação em ordem, preservando recycle→spawn no mesmo slot.
2. Limpar grade e atualizar HP dos obstáculos descontando dano GPU ainda não reconhecido pela CPU.
3. Mover asteroides/naves, transicionar estados, processar contato e disparos das naves.
4. Montar grade espacial com cabeças por célula e listas de slots.
5. Aplicar comandos de dano direto/círculo/linha e disparos externos.
6. Avançar projéteis, testar primeiro contato, aplicar dano e devolver slots ao pool.
7. Finalizar mortes uma única vez. HP usa CAS sobre bits de float, sem exigir extensão de atomics de float.
8. Resolver consultas de targeting por alcance/cone.
9. Quando houver espaço no canal de retorno, compactar relatório assíncrono.

Com `mass_gpu_separation` habilitado, entre a montagem da grade e o dano são executados: cálculo dos afastamentos em um SSBO separado (binding 13, 8 bytes/slot), aplicação, limpeza das cabeças e reconstrução da grade nas posições corrigidas. Cada invocação escreve somente o próprio slot; o cálculo lê posições estáveis e a barreira antecede sua aplicação. A grade usada também por tiros/targeting fica atualizada. O scratch é inteiramente sobrescrito antes de cada uso, inclusive após reset; não exige readback nem limpeza extra.

A separação consulta até 12 links por célula em nove células e usa até 12 contatos. O tamanho da célula é aumentado, quando necessário, para comportar a soma dos dois maiores raios e o padding. Correção suave limitada por velocidade, respeitando raio individual, barreiras e planeta. Pares coincidentes recebem direções opostas derivadas dos slots. Naves nos estados de ataque/rotação permanecem fixas e os móveis cedem espaço. Consultas limitadas não garantem ausência absoluta de sobreposição em alta densidade; posições reservadas de ataque ainda são uma evolução separada. Esse recurso é GPU: o fallback CPU mantém a dispersão de spawn, mas não aplica a nova separação.

`enemy_sim_render.glsl` lê os mesmos buffers de inimigos/projéteis e escreve diretamente nos buffers nativos de MultiMesh. Não existe caminho de posições GPU→CPU→GPU para renderizar. No backend autoritativo, inimigos e projéteis agora usam 16 floats: 12 de transformação e quatro de cor. A cor dos inimigos representa HP/flash; o HP inicial é individual, inclusive após sorteio. A referência de transformações sem simulação continua usando 12 floats. Mortos recebem escala zero imediatamente, antes da confirmação CPU. Listas de membros dos batches ainda são mantidas na CPU e enviadas ao backend; não é um sistema sem qualquer upload.

O backend nunca libera o RID emprestado do MultiMesh. Seus buffers, shaders, pipelines e uniform sets são próprios, liberados ao sair da cena. Sem RenderingDevice, o runtime escolhe CPU na inicialização; erro após início da simulação GPU é registrado em `backend_error` e interrompe novos passos. Não tenta reconstruir silenciosamente uma onda usando snapshots CPU incompletos.

## Canal CPU/GPU e limites

| Recurso | Limite atual |
| --- | ---: |
| Inimigos no runtime real | 10.000 |
| Arquétipos por World | 64 |
| IDs de obstáculos por sessão | 128 |
| Consultas estáticas de targeting por sessão | 256 |
| Projéteis GPU simultâneos | 4.096 |
| Comandos por passo GPU | 4.096 |
| Fila de ataques CPU | 8.192 |
| Mortes por página de relatório | 2.048 |
| Feedback cosmético de dano por relatório | 128 |
| Histórico de hits por projétil | 16 handles |
| Relatório fixo atual | 78.368 bytes |

Por padrão, solicita-se relatório a cada três **passos de simulação**, com no máximo um readback em voo. Inclui dano cumulativo ao planeta/obstáculos, contadores de tiros, até 256 resultados de alvo, 2.048 mortes de 32 bytes com posição e 128 feedbacks de dano. Em 60 ticks/s, o teto nominal atual desse canal é cerca de 1,57 MB/s, podendo ser menor conforme latência. O relatório anterior era de 41.488 bytes; não aplicar seu custo aos novos efeitos. No benchmark com um passo por frame renderizado, a frequência pode ser diferente. Não há readback periódico do estado completo; `request_diagnostic()` existe somente para testes.

Overflow de mortes não perde recompensas: slots mortos permanecem pendentes e são drenados nos próximos relatórios. Eventos repetidos são descartados pela geração; reset usa uma nova época para rejeitar callbacks antigos. O pool não reutiliza um slot morto até o ACK CPU, portanto uma explosão grande pode temporariamente atrasar novos spawns.

HP dos obstáculos combina snapshot CPU com dano cumulativo GPU e ACK, evitando ressuscitar barreiras enquanto o readback está atrasado. Dano/kill/credits são aplicados pelo bridge, e a última recompensa chega antes do resumo da onda.

`apply_damage` e `fire_projectile` retornam **aceitação do comando**, não confirmação de dano/slot de tiro. `damage_circle` e `damage_line` retornam 0/1 de rejeição/aceitação, não contagem síncrona de acertos. Saturação real de projéteis aparece em `dropped_projectiles`. O adaptador dos satélites envia um projétil GPU completo, preservando `hit_radius`, para não confundir aceitação de segmento com colisão.

Targeting entrega snapshots assíncronos, não posição instantânea. As torres consomem o resultado atualizado; consultas são identificadas por origem/alcance/direção/cone e destinam-se a montagens estáticas. Muitos observadores móveis exigirão registro/atualização/liberação por ID, em vez de gerar chaves indefinidamente. A grade atual é 128×128 com célula de 128 unidades; posições além dela são agrupadas nas células de borda, o que degrada consultas densas. AABB visual: XZ ±4.096, Y ±512.

## Benchmarks release

Sem processos Godot concorrentes e com VSync desligado. O intervalo observado tem piso próximo de 11,1 ms; não atribuir esse piso somente ao custo do jogo nem prometer FPS ilimitado. São amostras curtas, não soak tests.

### Carga isolada: todos visíveis, população exata

30 frames de aquecimento + 120 amostras; distribuição 60/25/10/5, anel de raio 1.200–1.900, oito barreiras lógicas e 32 emissores aliados. Um passo fixo de 1/60 s por frame amostrado. Readback de diagnóstico ao final confirma a população realmente viva na GPU.

| Vivos GPU | Mediana frame (ms) | p95 (ms) | Preparo CPU da simulação (ms) |
| ---: | ---: | ---: | ---: |
| 350 | 11,113 | 11,174 | 0,119 |
| 1.000 | 11,115 | 11,167 | 0,125 |
| 5.000 | 11,105 | 11,216 | 0,122 |
| 10.000 | 11,111 | 11,177 | 0,127 |

Oito Nodes de batches, dez draw calls observados. Caso 10.000: 321 tiros ativos e zero rejeitados. JSON: [isolado release](mass_enemy_gpu_release_benchmark.json). Referência tools: [isolado GPU](mass_enemy_gpu_benchmark.json). Antes, a mesma carga de combate na CPU tinha mediana 168,70 ms e p95 311,24 ms no binário tools; a comparação aponta remoção do gargalo, não uma razão universal de aceleração.

### Nível real: spawn gradual e torres reais

`GridCombatLevel`, preparação e ticks normais do engine, 50 spawn points, quatro naves aliadas, três blocos, quatro blasters, dois lasers e dois miners. Sem chamada manual a `step()`. 180 amostras após terminar o spawn. Mortes reduzem a população; a câmera do nível não foi ampliada para enquadrar todos os pontos.

| Total gerado | Pico vivo | Vivos durante amostras | Mediana frame (ms) | p95 (ms) |
| ---: | ---: | ---: | ---: | ---: |
| 5.000 | 4.895 | 4.737–4.895 | 11,111 | 11,460 |
| 10.000 | 9.757 | 9.757 | 11,092 | 11,358 |

Caso 10.000: 243 mortes e 243 projéteis ativos; nenhum tiro rejeitado. JSON: [nível release](mass_enemy_gpu_game_release_benchmark.json), [nível tools](mass_enemy_gpu_game_benchmark.json). Quantidade de mortes varia com RNG/tempo normal da cena; não comparar números exatos como se a fixture fosse determinística. `physics_median_ms` é o monitor de física do engine, não tempo de compute GPU.

Os campos `simulation_median_ms` e `upload_median_ms` medem preparo/agendamento CPU. `viewport_gpu_median_ms` mede viewport, podendo não incluir o compute externo. Tempo entre frames é a medida de ponta a ponta usada aqui.

## Reprodução e testes

```powershell
.\tests\run_mass_enemy_tests.ps1 -GPU
.\tests\run_mass_enemy_tests.ps1 -GPU -GPUCombatBenchmark
```

Quinze testes no runner, além da importação, incluindo referência CPU, backend GPU, integração real, playtest de 5.000, perfil legado e regressões existentes. O teste GPU verifica trajetórias/estados, projéteis com varredura, barreira rotacionada, dano concorrente/recompensa única, 3.000 mortes em páginas, 4.096 projéteis com overflow/recuperação, handles antigos e reset com readback em voo. Também compara buffers de MultiMesh com estado GPU mesmo quando o snapshot CPU foi adulterado, verifica ocultação de mortos antes do ACK, tumble/flash, desaceleração e piercing sem dano repetido.

O teste funcional do nível confirma spawn temporizado, pausa, montagem de torres, blaster adquirindo/matando um alvo estacionário de fixture, créditos, restart e banco da última recompensa. Alvo estacionário isola aquisição/dano; não comprova acerto garantido contra asteroide com desvio lateral. Benchmark executa os três tipos de torre com o roster móvel normal.

Para repetir em release, exportar para uma pasta de teste separada. O template instalado rejeita scene path na linha de comando. Criar nessa pasta um `override.cfg` com `[application]` e `run/main_scene="res://tests/mass_enemy_gpu_game_test.tscn"`; executar o binário sem scene path, com `-- --benchmark --output=caminho.json`. Para a carga isolada, apontar o override para `res://tests/mass_enemy_benchmark.tscn` e usar `-- --gpu-simulation --output=caminho.json`. Esse override fica somente junto do binário de teste, nunca no projeto ou distribuição normal. Mecanismo descrito na [documentação de ProjectSettings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html).

Conferir código de saída, ausência de `ERROR`/`SCRIPT ERROR` e marcador de sucesso; timeout/saída zero sozinhos não bastam. O teste legado de avoidance continua com falha conhecida, fora dos quinze aprovados; detalhes e reprodução em [Runtime](MASS_ENEMY_RUNTIME.md).

## Ainda fora do aceite final

Debris ofensivo, upgrades, HP por zona/sorteio, desaceleração e feedback já foram portados; conferir diferenças intencionais no mapa de paridade. Inimigos não se separam entre si; sobreposição nos pontos e excesso de modelos tornam a cena densa pouco legível. Blasters usam mira balística no snapshot, sem antecipação automática. Falta teste prolongado, hardware mínimo e resolver/aceitar a diferença de rotas do algoritmo legado. Essas pendências são o passo 7.3c; não justificam declarar rollout concluído ou apagar o caminho antigo.
