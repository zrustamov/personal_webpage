# Grade RAG

Production-ready grader for programming assignments using:
- BM25 retrieval over expert-graded examples
- OpenAI Chat Completions for rubric-based scoring

## Features
- No hardcoded secrets
- Environment-variable and CLI configuration
- Structured logging
- Retry logic for transient API failures
- Safe file handling and validation

## Requirements
- Python 3.10+
- OpenAI API key

Install dependencies:

```bash
pip install -r requirements.txt
```

## Configuration
Set environment variables (PowerShell example):

```powershell
$env:OPENAI_API_KEY="your_api_key"
$env:OPENAI_MODEL="gpt-4o-mini"  # optional
$env:GRADER_TEMPERATURE="0.1"    # optional
$env:GRADER_MAX_TOKENS="500"     # optional
$env:GRADER_MAX_RETRIES="3"      # optional
$env:LOG_LEVEL="INFO"            # optional
```

You can also pass values via CLI flags.

## Usage

```bash
python grader.py \
  --qa-file qa.json \
  --expert-file qa_expert_graded.json \
  --criteria-file grading_criteria.json \
  --output-file graded_results.json
```

## Output
The script writes a JSON file with graded answers for each question.

## Security Notes
- Do not commit `.env` or API keys.
- Rotate compromised keys immediately.
- Use scoped project keys where possible.
