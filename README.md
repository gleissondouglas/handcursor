# HandCursorApp

HandCursorApp é um aplicativo nativo para macOS que permite controlar o cursor do sistema utilizando visão computacional baseada em gestos manuais. O motor M4 captura o movimento e os gestos da mão em tempo real via câmera (com filtros avançados e persistência de rastreamento).

## Arquitetura

O projeto foi totalmente refatorado utilizando os princípios do Clean Architecture e SOLID. Cada camada tem uma responsabilidade única e se comunica de cima para baixo de forma isolada.

O pipeline de dados é:
`Camera` -> `Vision` -> `HandModel` -> `GestureRecognizer` -> `GestureStateMachine` -> `CursorController` -> `MouseEvents`

## Estrutura de Pastas

- `App/`: Inicialização (main) e coordenação das camadas (AppController).
- `Camera/`: Controle absoluto da câmera, delegando frames de vídeo sem conhecimento sobre Visão Computacional.
- `Vision/`: Interação isolada com o Vision Framework da Apple. Transforma frames em um modelo de dados independente.
- `Models/`: Modelos de dados puros que trafegam entre as camadas, sem amarras com frameworks de UI ou Visão.
- `Gestures/`: Lógica de identificação de gestos (Pinça e Arraste) controlada por uma Máquina de Estados (GestureStateMachine).
- `Cursor/`: Cálculo de limites, filtros e execução do mapeamento do mouse virtual para o sistema (MouseEvents).
- `Filters/`: Filtros matemáticos para suavização do movimento do cursor (LowPass, One Euro Filter).
- `Utils/`: Utilitários gerais do projeto (Logger, Constantes globais sem hardcode e extensões de código).

## Tecnologias Utilizadas

- **Swift**
- **Vision Framework** (Para detecção dos Hand Poses)
- **AVFoundation** (Para captura nativa da câmera)
- **CoreGraphics** e **CGEvent** (Para interação no nível do sistema)
- **Cocoa**

## Como Executar

O projeto é compilado via linha de comando chamando diretamente o compilador Swift.

1. Na raiz do projeto, certifique-se de dar permissão de execução:
```bash
chmod +x run.sh
```
2. Execute o script:
```bash
./run.sh
```

*(Opcionalmente, descomente a última linha do arquivo `run.sh` ou chame manualmente o `./HandCursorApp/HandCursorApp/HandCursor` gerado para rodar a aplicação logo após a compilação).*

## Permissões Necessárias do macOS

Como é um aplicativo de acessibilidade e captura em tempo real, ele necessitará de permissões do sistema quando rodado pela primeira vez:

1. **Permissão de Câmera:** Necessário para captura do stream de vídeo pelo AVFoundation.
2. **Permissão de Acessibilidade:** Necessário para o `CGEvent` poder despachar e mover o mouse a nível do sistema (Configurações do Sistema > Privacidade e Segurança > Acessibilidade).

## Roadmap

- [ ] Melhorar inferência em casos de baixa iluminação.
- [ ] Adicionar mais gestos (por exemplo, scroll do mouse, right click).
- [ ] Implementar interface de configuração (UI).
- [ ] Adicionar suporte a múltiplos monitores.

## Licença
MIT
