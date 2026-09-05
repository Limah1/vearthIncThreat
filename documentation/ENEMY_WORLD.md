# EnemyWorld — fundação do passo 4

O `EnemyWorld` é um Node proprietário dos dados de todos os inimigos da nova arquitetura. Cada inimigo ocupa um slot em arrays pré-alocados. Asteroides e naves compartilham o sistema, com índices de arquétipo e estados diferentes.

## Uso no editor

Abra `res://src/prototypes/mass_enemies/MassEnemyFoundation.tscn` e execute com **F6**.

- O teste cria 40 SpawnPoints.
- `MassEnemyTestConfig.tres` configura 25 inimigos por ponto a cada segundo.
- A onda atinge 10.000 spawns e 10.000 ativos em aproximadamente dez segundos, dependendo do processamento disponível.
- O painel mostra os contadores; os inimigos ainda não são desenhados ou simulados.
- Os pesos do roster são 60/25/10/5 para pequeno/médio/grande/nave.

Os campos de ritmo e roster ficam no `MassEnemyTestConfig.tres`; a capacidade simultânea fica no Node `EnemyWorld` (configure antes da inicialização). Não se altera o nível selecionado nem o spawner principal para executar esta cena. O protótipo ignora o estado de preparação do GameManager para rodar isoladamente.

## API e propriedade

- `initialize()`: aloca arrays uma única vez; padrão de 10.000 slots.
- `register_catalog(catalog)`: valida os Resources e registra uma cópia compartilhada por arquétipo. Repetir o mesmo catálogo é permitido; um Resource diferente com um ID já registrado é rejeitado. Meshes e materiais continuam compartilhados.
- `request_spawn(enemy, position) -> int`: inicializa um slot e devolve um handle; `-1` indica rejeição. Não instancia a cena visual.
- `is_handle_valid(handle)`: verifica o slot ativo e sua geração.
- `recycle(handle)`: devolve um slot em O(1), usando remoção por troca na lista de ativos. Os handles dos outros inimigos continuam válidos.
- `reset_world()`: devolve todos os slots e mantém a alocação e o catálogo para a próxima onda.
- `get_active_handle(index)`: percorre a lista densa de ativos.
- `get_enemy_snapshot(handle)`: snapshot alocado para inspeção/teste, não para loops por frame.
- `flush_events()`: publica contadores acumulados de spawns, reciclagens e rejeições. Também é chamado pelo `_process()`.

Os arrays guardam posição, velocidade, HP, estado, arquétipo, timer de ataque, orientação e alvo. A lista de ativos, a lista de slots livres e as gerações ficam separadas. Os sistemas futuros acessam esses arrays sob propriedade do World, na thread principal; consumidores não devem redimensioná-los ou alterar metadados de alocação.

As definições são compartilhadas por arquétipo; posição, HP atual, timer e alvo são dados individuais. O World escolhe o estado inicial; `EnemyCombat` implementa a referência CPU. Com `EnemyGPUCombat`, o World mantém somente a autoridade de alocação: `gpu_changes` é um journal ordenado de spawn/recycle, e a GPU é dona do estado simulado. Posição/HP/estado nos arrays CPU são snapshots de targeting, não o estado completo atual. Não alterar esses arrays para movimentar um inimigo GPU. `mutation_revision` invalida caches de grade/render quando ocorre spawn ou recycle, inclusive se a quantidade de ativos não mudar.

## Handles

O perfil opcional `use_legacy_rules` é definido antes do registro do catálogo. Ele aplica zona e regras a cópias dos EnemyData, sem modificar Resources autorados. Cada spawn sorteia seu HP em 1–5 quando o perfil de asteroide está ativo; o comando GPU recebe o HP sorteado, não o máximo do arquétipo. O HP inicial individual também fica no estado GPU para normalizar o feedback visual. Alterar perfil/zona requer recriar o World, normalmente recarregando o nível.

Um inteiro de 64 bits combina slot (32 bits inferiores) e geração (31 bits positivos superiores). Cada alocação recebe uma geração nova, única no processo. Isso impede que um handle antigo alcance um inimigo que reutilizou seu slot, inclusive após reset ou em outro World. Não há reaproveitamento após overflow: a alocação é rejeitada.

Handles pertencem à sessão atual; não são identificadores persistentes de save games. O `enemy_id` do Resource identifica o arquétipo, não uma instância viva.

## Integração com o spawner

Atribua `enemy_world` no `MassEnemySpawner`. O spawner registra seu catálogo e chama `request_spawn()`. A contagem só aumenta quando existe um slot alocado. Pool cheio preserva a requisição e o ciclo em andamento; nenhum inimigo ativo é substituído para abrir espaço.

`spawn_requested` serve como observação após a confirmação. Não o conecte novamente a `request_spawn()`. O World não emite eventos individuais; `events_flushed` agrega o trabalho desde o último flush. Esses contadores ainda não concedem créditos ou registram mortes no gameplay antigo.

`total_enemies` continua sendo o total da onda, não o limite de vivos. É possível configurar uma onda maior que a capacidade e ir liberando espaço com `recycle()`. Para iniciar uma sessão vazia: pare/reset o spawner, execute `reset_world()` e inicie novamente o spawner.

## Verificação

Os testes cobrem slots livres, pool cheio, remoção intermediária, gerações, reset, handles de outro World, registro de catálogo, posição inválida, eventos agregados e integração com pausa de spawn por falta de capacidade.

O teste integrado cria 10.000 inimigos usando 40 pontos e quatro arquétipos, verifica os handles e confirma que o número de Nodes não aumenta durante o spawn. Isso valida armazenamento e integração; não é um benchmark de renderização nem comprova 60/120 FPS.

```powershell
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --editor --path 'E:\GODOT\vearthIncThreat' --quit
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/enemy_world_test.tscn' --quit-after 120
```

O passo 5 conecta esses dados a MultiMeshes e o passo 6.2 entrega simulação compute autoritativa. A cena Foundation continua intencionalmente sem renderização; use `MassEnemyArena.tscn` para a apresentação e o combate. Em modo GPU, use `reset_combat()` para reiniciar a sessão inteira e invalidar readbacks pendentes. Veja [runtime e medições](MASS_ENEMY_RUNTIME.md).
