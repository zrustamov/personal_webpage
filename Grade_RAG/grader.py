import argparse
import json
import logging
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List

from openai import OpenAI
from rank_bm25 import BM25Okapi

LOGGER = logging.getLogger("grader")


@dataclass
class GraderConfig:
    api_key: str
    model: str = "gpt-4o-mini"
    temperature: float = 0.1
    max_tokens: int = 500
    max_retries: int = 3


class ProgrammingAssignmentGrader:
    def __init__(self, config: GraderConfig):
        self.config = config
        self.client = OpenAI(api_key=config.api_key)
        self.grading_criteria: Dict[str, Any] = {}
        self.expert_examples: Dict[str, Any] = {}
        self.student_data: Dict[str, Any] = {}
        self.bm25: BM25Okapi | None = None
        self.expert_metadata: List[Dict[str, Any]] = []

    @staticmethod
    def _read_json(path: str | Path) -> Dict[str, Any]:
        file_path = Path(path)
        if not file_path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")
        with file_path.open("r", encoding="utf-8") as file:
            return json.load(file)

    def load_data(self, qa_file: str, expert_file: str, criteria_file: str) -> None:
        self.student_data = self._read_json(qa_file)
        self.expert_examples = self._read_json(expert_file)
        self.grading_criteria = self._read_json(criteria_file)
        self._setup_bm25()

    @staticmethod
    def _tokenize(text: str) -> List[str]:
        cleaned = re.sub(r"[^\w\s]", " ", text.lower())
        return cleaned.split()

    def _setup_bm25(self) -> None:
        expert_questions: List[List[str]] = []
        self.expert_metadata = []

        for q_id, data in self.expert_examples.items():
            question = data.get("question", "")
            if not question:
                continue
            expert_questions.append(self._tokenize(question))
            self.expert_metadata.append(
                {
                    "q_id": q_id,
                    "question": question,
                    "answer": data.get("answer", ""),
                    "grade": data.get("expert_grade", ""),
                }
            )

        if not expert_questions:
            raise ValueError("No valid expert examples were found for BM25 indexing.")

        self.bm25 = BM25Okapi(expert_questions)
        LOGGER.info("BM25 setup complete with %d expert examples.", len(expert_questions))

    def find_best_expert(self, question: str) -> Dict[str, Any]:
        if self.bm25 is None:
            raise RuntimeError("BM25 index is not initialized. Call load_data() first.")

        query_tokens = self._tokenize(question)
        scores = self.bm25.get_scores(query_tokens)
        best_idx = max(range(len(scores)), key=lambda idx: scores[idx])

        result = self.expert_metadata[best_idx].copy()
        result["bm25_score"] = float(scores[best_idx])
        return result

    def build_criteria_text(self) -> str:
        lines = ["Grading Criteria:\n"]
        for criterion in self.grading_criteria.get("criteria", []):
            category = criterion.get("category", "Unnamed Category")
            lines.append(f"{category}:")

            levels = criterion.get("Qiymət səviyyələri", {}) or criterion.get("QiymÉ™t sÉ™viyyÉ™lÉ™ri", {})
            for level, desc in levels.items():
                level_lc = level.lower()
                if "yuksek" in level_lc or "yüksək" in level_lc:
                    score = "2"
                elif "orta" in level_lc:
                    score = "1"
                elif "asagi" in level_lc or "aşağı" in level_lc:
                    score = "0"
                else:
                    score = "?"
                lines.append(f"- {score} points: {desc}")
            lines.append("")

        return "\n".join(lines).strip()

    def create_prompt(self, question: str, student_answer: str) -> str:
        best_expert = self.find_best_expert(question)
        criteria_text = self.build_criteria_text()

        return (
            "You are a strict programming assignment grader.\n\n"
            "CURRENT QUESTION AND STUDENT ANSWER:\n"
            f"Question: {question}\n"
            f"Student answer: {student_answer}\n\n"
            "MOST SIMILAR EXPERT EXAMPLE (use it as benchmark):\n"
            f"Expert question: {best_expert['question']}\n"
            f"Expert answer: {best_expert['answer']}\n"
            f"Expert grade: {best_expert['grade']}\n\n"
            f"{criteria_text}\n\n"
            "RULES:\n"
            "- Syntax errors must reduce Syntax score to 0 or 1.\n"
            "- Nonsense content should receive 0 in all criteria.\n"
            "- Non-working code should receive low scores.\n"
            "- Do not inflate grades beyond the expert benchmark.\n\n"
            "Output format:\n"
            "Qiymətləndirmə:\n"
            "• Sintaksis: [0/1/2]\n"
            "• Məlumat tipi: [0/1/2]\n"
            "• Daxiletmə və çıxış: [0/1/2]\n"
            "• Strukturluluq: [0/1/2]\n"
            "• Yaradıcı əlavələr: [0/1/2]\n"
            "➡️ Cəmi: [sum] bal"
        )

    def grade_answer(self, question: str, answer: str) -> str:
        prompt = self.create_prompt(question, answer)

        for attempt in range(1, self.config.max_retries + 1):
            try:
                response = self.client.chat.completions.create(
                    model=self.config.model,
                    messages=[
                        {
                            "role": "system",
                            "content": (
                                "You are a strict programming grader. Penalize syntax errors, "
                                "non-working code, and meaningless answers."
                            ),
                        },
                        {"role": "user", "content": prompt},
                    ],
                    temperature=self.config.temperature,
                    max_tokens=self.config.max_tokens,
                )
                return (response.choices[0].message.content or "").strip() or "No grade returned."
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning(
                    "OpenAI request failed (attempt %d/%d): %s",
                    attempt,
                    self.config.max_retries,
                    exc,
                )
                if attempt == self.config.max_retries:
                    return f"Error: {exc}"
                time.sleep(2 ** (attempt - 1))
        return "Error: Unknown grading failure."

    def grade_all(self) -> Dict[str, Any]:
        results: Dict[str, Any] = {}

        for q_id, q_data in self.student_data.items():
            question = q_data.get("question", "")
            answers = q_data.get("answers", [])
            LOGGER.info("Grading %s with %d answers.", q_id, len(answers))

            graded_answers: List[Dict[str, Any]] = []
            for index, answer in enumerate(answers, start=1):
                grade = self.grade_answer(question, answer)
                graded_answers.append(
                    {
                        "student_id": index,
                        "answer": answer,
                        "grade": grade,
                    }
                )

            results[q_id] = {"question": question, "graded_answers": graded_answers}

        return results

    @staticmethod
    def save_results(results: Dict[str, Any], output_file: str | Path) -> None:
        output_path = Path(output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with output_path.open("w", encoding="utf-8") as file:
            json.dump(results, file, ensure_ascii=False, indent=2)
        LOGGER.info("Results saved to %s", output_path)

    def run(self, qa_file: str, expert_file: str, criteria_file: str, output_file: str) -> Dict[str, Any]:
        LOGGER.info("Loading input files.")
        self.load_data(qa_file, expert_file, criteria_file)
        LOGGER.info("Grading all answers.")
        results = self.grade_all()
        LOGGER.info("Saving results.")
        self.save_results(results, output_file)
        LOGGER.info("Done.")
        return results


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Grade programming assignments using OpenAI + BM25 retrieval.")
    parser.add_argument("--qa-file", default="qa.json", help="Path to student QA json.")
    parser.add_argument("--expert-file", default="qa_expert_graded.json", help="Path to expert graded json.")
    parser.add_argument("--criteria-file", default="grading_criteria.json", help="Path to grading criteria json.")
    parser.add_argument("--output-file", default="graded_results.json", help="Path to output graded results json.")
    parser.add_argument("--api-key", default=os.getenv("OPENAI_API_KEY"), help="OpenAI API key. Defaults to OPENAI_API_KEY.")
    parser.add_argument("--model", default=os.getenv("OPENAI_MODEL", "gpt-4o-mini"), help="OpenAI model name.")
    parser.add_argument("--temperature", type=float, default=float(os.getenv("GRADER_TEMPERATURE", "0.1")))
    parser.add_argument("--max-tokens", type=int, default=int(os.getenv("GRADER_MAX_TOKENS", "500")))
    parser.add_argument("--max-retries", type=int, default=int(os.getenv("GRADER_MAX_RETRIES", "3")))
    parser.add_argument(
        "--log-level",
        default=os.getenv("LOG_LEVEL", "INFO"),
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging verbosity.",
    )
    return parser


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )

    if not args.api_key:
        parser.error("OpenAI API key is required. Set OPENAI_API_KEY or pass --api-key.")

    config = GraderConfig(
        api_key=args.api_key,
        model=args.model,
        temperature=args.temperature,
        max_tokens=args.max_tokens,
        max_retries=args.max_retries,
    )

    grader = ProgrammingAssignmentGrader(config)
    try:
        grader.run(
            qa_file=args.qa_file,
            expert_file=args.expert_file,
            criteria_file=args.criteria_file,
            output_file=args.output_file,
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        LOGGER.exception("Grading failed: %s", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
