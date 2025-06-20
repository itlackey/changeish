# Configuration

`changeish` is highly configurable via environment variables, a `.env` file, or command-line arguments. This allows you to easily switch between local Ollama models and remote OpenAI-compatible APIs, customize prompt templates, and control changelog output.

## Environment Variables

Set these in your shell, CI environment, or a `.env` file in your project root.

| Variable              | Purpose                                                                                 | Example Value / Notes                                 |
|-----------------------|-----------------------------------------------------------------------------------------|-------------------------------------------------------|
| `CHANGEISH_MODEL`     | Default model to use for local (Ollama) generation. Overridden by `--model`.            | `qwen2.5-coder`                                       |
| `CHANGEISH_API_KEY`   | API key for remote generation (required if `--remote` is used).                         | `your_openai_api_key_here` or `your_groq_api_key_here`|
| `CHANGEISH_API_URL`   | Default API URL for remote generation. Overridden by `--api-url`.                       | `https://api.openai.com/v1/chat/completions`          |
| `CHANGEISH_API_MODEL` | Default API model for remote generation. Overridden by `--api-model`.                   | `gpt-4o-mini`, `compound-beta`, etc.                  |

You can also use a `.env` file to set these variables. See `.env.example` for detailed configuration for Ollama, OpenAI, Groq, and Azure OpenAI.


## Using a Custom Configuration File

You can specify a custom config file (in `.env` format) with the `--config-file` option:

```sh
changeish --config-file ./myconfig.env
```

## Example `.env` File

```env
# For local Ollama
CHANGEISH_MODEL=qwen2.5-coder

# For Groq API
CHANGEISH_API_URL="https://api.groq.com/openai/v1/chat/completions"
CHANGEISH_API_MODEL="compound-beta"
CHANGEISH_API_KEY=your_groq_api_key_here

# For OpenAI
CHANGEISH_API_MODEL=gpt-4o-mini
CHANGEISH_API_URL=https://api.openai.com/v1/chat/completions
CHANGEISH_API_KEY=your_openai_api_key_here

# For Azure OpenAI
# See .env.example for full Azure setup instructions
```

## Command-Line Overrides

Any environment variable can be overridden by the corresponding CLI flag:

- `--model` overrides `CHANGEISH_MODEL`
- `--api-model` overrides `CHANGEISH_API_MODEL`
- `--api-url` overrides `CHANGEISH_API_URL`

## Prompt Templates

- By default, `changeish` uses a built-in prompt template for changelog generation.
- You can provide your own template with `--prompt-template ./my_template.md`.
- The template should include clear instructions and optionally an example output (see `docs/prompt_template.md`).

## Version File Detection

- By default, `changeish` will look for common version files (`package.json`, `pyproject.toml`, etc.) to highlight version changes.
- You can specify a custom file with `--version-file path/to/file`.

## Tips

- For remote API usage, you **must** set a valid API key and URL.
- If you use Azure OpenAI, see the `.env.example` for the required environment variables and URL format.
- You can combine `.env` files, environment variables, and CLI flags for maximum flexibility.

> See the [README](../README.md) and [Installation](./installation.md) for more details and examples.