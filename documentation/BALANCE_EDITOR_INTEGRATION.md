# Balance Editor XLSX

## Estado atual

O editor de balanceamento está implementado e habilitado como plugin do Godot em
`addons/balance_editor`. Ele exporta os recursos atuais para um único arquivo
`.xlsx`, valida as alterações e injeta somente os campos permitidos de volta nos
arquivos `.tres`.

O fluxo cobre atualmente:

| Aba | Recursos | Campos |
|---|---|---|
| `Upgrades` | `src/resources/upgrades/**/*.tres` | custo, crescimento, nível máximo, incremento, percentual e desbloqueio inicial |
| `Turrets` | `src/resources/turrets/*.tres` | dano, cadência, alcance, cone, varredura e atualização de alvo |
| `Barriers` | `src/resources/barriers/*.tres` | vida, tamanho, distância e profundidade |
| `Levels` | `src/resources/levels/*.tres` | total de inimigos e inventário inicial do grid |
| `Schema` | metadados internos | projeto e versão do formato; aba oculta |

A topologia da skill tree não faz parte da planilha. Posições, pré-requisitos,
IDs e progresso comprado continuam sob responsabilidade do Skill Tree Designer,
do `UpgradeManager` e do save game.

## Uso no editor

1. Abra o projeto com Godot 4.7.2.
2. Localize o dock **Balance Editor** à direita.
3. Clique em **EXTRACT DATA (.XLSX)** e salve uma planilha nova.
4. Abra o arquivo no Excel, LibreOffice ou Google Sheets.
5. Altere somente as células amarelas da coluna `New Value`.
6. Salve ou baixe novamente no formato Microsoft Excel `.xlsx`.
7. No Godot, clique em **INJECT VALUES (.XLSX)** e selecione o arquivo.
8. Revise a quantidade de alterações e confirme a injeção.

Reinicie a cena em execução depois da importação. Instâncias já criadas ou
objetos em pool podem manter valores carregados anteriormente.

Arquivos `.xls` antigos não são suportados.

## Estrutura da planilha

Cada aba de dados usa as colunas abaixo:

| Coluna | Função | Editável? |
|---|---|---:|
| `Field ID` | identidade estável do campo no workbook | não |
| `System` | domínio de balanceamento | não |
| `Actor / Asset` | nome legível do recurso | não |
| `Property` | nome legível da propriedade | não |
| `Current Value` | valor presente no `.tres` na exportação | não |
| `New Value` | valor que será importado | sim |
| `Type` | tipo exigido pelo importador | não |
| `Minimum` / `Maximum` | limites aceitos | não |
| `Resource Path` | caminho técnico do recurso, oculto | não |
| `Property Key` | propriedade técnica, oculta | não |
| `Editing Notes` | orientação específica | não |

O cabeçalho fica congelado, os filtros são habilitados e a coluna editável é
destacada em amarelo. Números e booleanos são gravados como células tipadas.

## Tipos aceitos

| Tipo | Célula esperada | Exemplo |
|---|---|---|
| `int` | número inteiro | `12` |
| `float` | número | `1.25` |
| `bool` | booleano real | `TRUE` / `FALSE` |
| `vector2` | texto no formato `X, Y` | `40, 10` |

Texto como `"10"` é rejeitado quando o campo exige número. Um valor decimal é
rejeitado em campos inteiros. Percentuais usam a forma decimal: `0.15` equivale
a 15%.

## Validação e segurança

O importador usa uma allowlist criada em `balance_schema.gd`; alterar caminhos
ou nomes dentro do arquivo Excel não permite escrever propriedades arbitrárias.
Antes de salvar, ele verifica:

- projeto e versão do schema;
- presença de todas as abas, colunas e linhas registradas;
- IDs duplicados, ausentes, desconhecidos ou movidos de aba;
- colunas técnicas modificadas;
- tipo real da célula, mínimo e máximo;
- planilha desatualizada, comparando `Current Value` com o recurso atual;
- ordem dos ângulos e distâncias mínimas/máximas das torres;
- dimensões positivas da barreira.
- quantidade exigida de Ally Ships não pode superar o inventário inicial do level.

Depois da validação completa, o plugin cria um snapshot JSON em
`user://balance_backups/`, altera os recursos em memória e salva os `.tres`. Se
qualquer gravação falhar, os valores anteriores são restaurados e salvos
novamente.

## Criação de upgrades e IDs automáticos

O botão **New Upgrade** do Skill Tree Designer cria o `.tres` em
`src/resources/upgrades/` e gera automaticamente um ID no formato:

```text
UPG_<TIPO_NORMALIZADO>_<SEQUÊNCIA>
```

Exemplo: `UPG_LASERDAMAGE_001`.

A sequência é calculada recursivamente a partir dos upgrades existentes. IDs já
salvos nunca são substituídos, pois são usados pela árvore e pelo progresso do
jogador. Ao selecionar uma categoria diretamente no inspector de um recurso
novo, `UpgradeData` também preenche um ID vazio automaticamente no editor.

## Arquitetura

| Arquivo | Responsabilidade |
|---|---|
| `addons/balance_editor/balance_editor_plugin.gd` | dock, diálogos, confirmação, backup, aplicação e rollback |
| `addons/balance_editor/balance_schema.gd` | descoberta dos recursos e allowlist de campos/limites |
| `addons/balance_editor/xlsx_balance_codec.gd` | leitura e escrita Open XML usando `ZIPPacker`, `ZIPReader` e `XMLParser` |
| `addons/balance_editor/balance_import_validator.gd` | validação estrutural, tipada e entre campos |
| `src/resources/upgrade_data.gd` | geração e validação dos IDs de upgrade |

O codec aceita strings inline e shared strings, além de XML com ou sem prefixos
de namespace. Isso cobre o arquivo original e planilhas regravadas por editores
compatíveis com XLSX sem depender de Excel instalado, Python ou serviço web.

## Inclusão de novos campos de balanceamento

1. Garanta que o gameplay lê o valor de um `Resource` tipado, e não de uma
   constante ou estado temporário da instância.
2. Registre o campo na coleção correspondente de `balance_schema.gd`, com tipo,
   limites e nota de edição.
3. Se houver relação com outros campos, adicione a regra em
   `balance_import_validator.gd`.
4. Incremente `SCHEMA_VERSION` quando a mudança invalidar planilhas antigas.
5. Exporte uma planilha nova e execute os testes.

Player, inimigos, projéteis e outros valores ainda gravados diretamente em
cenas/scripts devem ser migrados para recursos de configuração antes de serem
expostos. A planilha deve representar valores-base, nunca vida atual, timers,
alvos, estado de pool ou progresso do jogador.

## Testes

No PowerShell:

```powershell
& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/balance_workbook_smoke_test.tscn'

& 'E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path 'E:\GODOT\vearthIncThreat' 'res://tests/upgrade_data_id_test.tscn'
```

O teste da planilha verifica exportação e leitura, células tipadas, uma alteração
válida, rejeição de tipo inválido e compatibilidade com uma planilha regravada
por uma biblioteca geral de XLSX quando o arquivo de round-trip está disponível.

## Limitações conhecidas

- somente `.xlsx` é suportado;
- fórmulas não são avaliadas pelo Godot; use valores literais;
- caminhos dos recursos ainda participam da identidade protegida da planilha;
- a ferramenta não envia o arquivo diretamente ao Google Drive;
- o hot reload de todas as instâncias e pools não é garantido;
- a skill tree gráfica continua sendo editada exclusivamente no designer.
