# PotIA 🍲

Assistente culinária com IA, do dado bruto ao app: raspagem de receitas → tokenizer próprio → fine-tuning QLoRA → API FastAPI com streaming → app Flutter.

```
potIA/
├── ml/                     Fases 1, 2 e 3
│   ├── scraper_potia.py        Fase 1 · raspagem + limpeza (clean_text)
│   ├── train_tokenizer.py      Fase 2 · tokenizer BPE com termos culinários
│   ├── format_dataset.py       Fase 2 · dataset ChatML/JSONL
│   ├── train_potia_model.py    Fase 3 · QLoRA (transformers + peft + trl)
│   └── amostras/               receitas de exemplo para rodar offline
├── backend/                Fase 4 · API FastAPI (JWT + SQLite + chat SSE)
└── potia_app/              Fase 5 · app Flutter (Provider)
```

## Fase 1 — Raspagem e limpeza

```bash
cd ml
pip install -r requirements.txt
python scraper_potia.py --sample
```

Fontes de dados:

| Opção | Uso |
|---|---|
| `--sample` | receitas de exemplo locais (funciona offline) |
| `--urls URL1 URL2` | páginas específicas |
| `--urls-file urls_receitas.txt` | uma URL por linha |
| `--sitemap URL --pattern /receita --limit 200` | descoberta automática |

A extração tenta JSON-LD `schema.org/Recipe` → microdata → seletores CSS. O scraper respeita `robots.txt` e `Crawl-delay`, espaça as requisições por domínio e tenta de novo em 429/5xx. Confira também os Termos de Uso de cada site.

Saídas: `ml/data/dados_receitas_brutos.csv` (listas em JSON nas colunas) e `ml/data/dados_receitas.txt`.

## Fase 2 — Tokenizer e dataset

```bash
python train_tokenizer.py
python format_dataset.py --samples-per-recipe 3 --val-ratio 0.1
```

- O tokenizer BPE usa `▁` como marcador de espaço e registra 56 expressões culinárias (`colher de sopa`, `banho-maria`, `fogo brando`, `refogar`...) como tokens únicos. O script mostra a economia de tokens e verifica se decodificar devolve exatamente o texto original. Saída: `ml/artifacts/tokenizer_potia/`.
- O dataset gera várias tarefas por receita (receita completa, só ingredientes, só preparo, tempo/rendimento, "o que faço com X", conversa de 2 turnos). A divisão entre treino e validação é feita por receita. Saídas: `ml/data/potia_train.jsonl` e `potia_val.jsonl`.

> O fine-tuning da Fase 3 usa o tokenizer do Qwen, porque os embeddings pré-treinados dependem do vocabulário original. O tokenizer da Fase 2 serve para análise do corpus e para treinar um modelo do zero.

## Fase 3 — Fine-tuning QLoRA (GPU)

No Google Colab (T4 ou A100), envie a pasta `ml/` com `data/` e rode:

```bash
pip install -r requirements-train.txt
python train_potia_model.py --profile t4
python train_potia_model.py --profile a100 --merge
```

| Parâmetro | Padrão |
|---|---|
| Modelo base | `Qwen/Qwen2.5-7B-Instruct` (`--base-model`) |
| Quantização | 4-bit NF4 + double quant |
| LoRA | r=16, alpha=32, dropout=0.05, todas as projeções lineares |
| Otimização | lr 2e-4, cosine, warmup 3%, `paged_adamw_8bit`, 3 épocas |
| Batch efetivo | 16 (perfis `t4`, `rtx`, `a100`) |

- A perda é calculada só na resposta da assistente (formato prompt/completion).
- O adaptador é salvo em `artifacts/potia-qwen2.5-7b/adapter/`. Com `--merge` (ou depois com `--merge-only`), o modelo completo vai para `.../merged/`.
- Para mesclar um 7B, são necessários cerca de 16 GB de RAM/VRAM. No Colab gratuito, use `--base-model Qwen/Qwen2.5-3B-Instruct` ou sirva o adaptador direto pelo vLLM.

## Fase 4 — API

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env
python main.py
```

Documentação interativa em http://localhost:8000/docs. Testes: `pytest -v`.

> **Windows com Python do `uv`:** se `python` abrir a Microsoft Store, use `python3.14` no lugar dele e instale as dependências com `python3.14 -m pip install --user --break-system-packages -r requirements.txt`. O mesmo vale para os scripts de `ml/`.

| Endpoint | Descrição |
|---|---|
| `POST /api/v1/auth/register` | `{name, email, password}` → JWT |
| `POST /api/v1/auth/login` | `{email, password}` → JWT |
| `GET /api/v1/auth/me` | usuário do token |
| `POST /api/v1/chat` | `{messages: [{role, content}], stream: true}` → SSE |
| `GET /health` | estado da API e do motor |

Eventos SSE: `{"type":"token","content":"..."}`, `{"type":"done"}` e `{"type":"error","detail":"..."}`.

Motor de inferência (`POTIA_LLM_ENGINE` no `.env`):

| Valor | Quando usar |
|---|---|
| `mock` | desenvolver o app sem GPU (respostas prontas, com streaming) |
| `ollama` | modelo local pronto, sem treino (Windows/macOS/Linux, GPU de 8 GB já basta) |
| `transformers` | modelo carregado na própria API (`pip install -r requirements-gpu.txt`) |
| `vllm` | produção: `bash scripts/serve_vllm.sh` (Linux/WSL) e a API repassa o stream |

Para usar o Ollama, instale-o, baixe o modelo e troque `POTIA_LLM_ENGINE=ollama` no `.env`:

```bash
winget install Ollama.Ollama
ollama pull qwen2.5:7b
```

O `qwen2.5:7b` (~4,7 GB) é o mesmo modelo base do fine-tuning da Fase 3. Outro modelo pode ser usado com `POTIA_OLLAMA_MODEL`.

Gere uma chave JWT nova com:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
```

## Fase 5 — App Flutter

As pastas de plataforma (android/ios/web) são geradas pelo Flutter. O comando abaixo não sobrescreve os arquivos existentes:

```bash
cd potia_app
flutter create . --project-name potia_app --org com.potia
flutter pub get
flutter run
```

- **Emulador Android:** usa `http://10.0.2.2:8000` automaticamente. O `AndroidManifest.xml` já libera HTTP (`usesCleartextTraffic`) para desenvolvimento.
- **Celular físico:** `flutter run --dart-define=API_BASE_URL=http://IP_DO_PC:8000`.
- **iOS:** para HTTP local, adicione `NSAppTransportSecurity → NSAllowsLocalNetworking` no `Info.plist`.

Estrutura de `lib/`: `models/` (dados), `services/` (HTTP, parser SSE, armazenamento), `providers/` (estado com ChangeNotifier), `views/` (splash, onboarding, auth, chat) e `core/` (tema, rotas, configuração, validações).

Testes: `flutter test`.
