from openai import OpenAI
from pathlib import Path
import json
import os


client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

MODEL = "gpt-5-nano-2025-08-07"


PAGE_NOTES_SCHEMA = {
    "type": "object",
    "properties": {
        "pages": {
            "type": "array",
            "description": "One Markdown note for each PDF page.",
            "items": {
                "type": "object",
                "properties": {
                    "page_number": {
                        "type": "integer",
                        "description": "The 1-based page number in the PDF."
                    },
                    "markdown": {
                        "type": "string",
                        "description": "Concise Markdown notes for this page."
                    }
                },
                "required": ["page_number", "markdown"],
                "additionalProperties": False
            }
        }
    },
    "required": ["pages"],
    "additionalProperties": False
}


def build_pdf_notes_prompt() -> str:
    return """
You are an academic PDF note-taking assistant.

Task:
Read the entire PDF and generate concise Markdown notes for each page.

You must use:
- The page text
- Images, diagrams, charts, tables, formulas, arrows, and visual layout
- The spatial structure of each page

Output:
Return a JSON object with a "pages" array.
Each item must contain:
- page_number: the page number, starting from 1
- markdown: the Markdown note for that page

Markdown format for each page:

# Page <page_number>: <short inferred title>

## Main Idea
<Explain the main idea of this page in 2-4 concise sentences.>

## Key Terms
- **<term>**: <brief explanation based on this page>
- **<term>**: <brief explanation based on this page>

Rules:
- Generate one item for every page in the PDF.
- Do not skip pages.
- Focus on each page individually.
- Keep each page note concise.
- Explain only important technical terms, academic terms, formulas, methods, concepts, or abbreviations.
- Do not include obvious everyday words as key terms.
- If a page has no important technical terms, omit the "## Key Terms" section for that page.
- If a page is blank or contains almost no useful content, still create a short note saying that the page has limited content.
- Do not invent information that is not supported by the PDF.
- The markdown field should contain Markdown only.
- Do not wrap Markdown in ```md.
"""


def upload_pdf(pdf_path: str):
    """
    Upload the PDF to OpenAI Files API and return the file object.
    """
    with open(pdf_path, "rb") as f:
        uploaded_file = client.files.create(
            file=f,
            purpose="user_data"
        )

    return uploaded_file


def generate_all_page_notes_json(pdf_path: str) -> dict:
    """
    Send the whole PDF to the model and ask it to return JSON:
    {
      "pages": [
        {
          "page_number": 1,
          "markdown": "..."
        }
      ]
    }
    """
    uploaded_file = upload_pdf(pdf_path)

    response = client.responses.create(
        model=MODEL,
        input=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_file",
                        "file_id": uploaded_file.id
                    },
                    {
                        "type": "input_text",
                        "text": build_pdf_notes_prompt()
                    }
                ]
            }
        ],
        text={
            "format": {
                "type": "json_schema",
                "name": "pdf_page_notes",
                "strict": True,
                "schema": PAGE_NOTES_SCHEMA
            }
        },
        max_output_tokens=20000
    )

    raw_json = response.output_text

    try:
        data = json.loads(raw_json)
    except json.JSONDecodeError as e:
        raise ValueError(
            f"Model did not return valid JSON.\n\nRaw output:\n{raw_json}"
        ) from e

    return data


def save_notes(data: dict, output_dir: str):
    """
    Save:
    1. notes.json
    2. notes/page_001.md, page_002.md, ...
    """
    output_path = Path(output_dir)
    notes_dir = output_path / "notes"

    output_path.mkdir(parents=True, exist_ok=True)
    notes_dir.mkdir(parents=True, exist_ok=True)

    json_path = output_path / "notes.json"

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    pages = data.get("pages", [])

    for page in pages:
        page_number = page["page_number"]
        markdown = page["markdown"].strip()

        md_path = notes_dir / f"page_{page_number:03d}.md"

        with open(md_path, "w", encoding="utf-8") as f:
            f.write(markdown + "\n")

        print(f"Saved: {md_path}")

    print(f"Saved JSON: {json_path}")


def pdf_to_page_notes(pdf_path: str, output_dir: str):
    data = generate_all_page_notes_json(pdf_path)
    save_notes(data, output_dir)

'''
if __name__ == "__main__":
    pdf_to_page_notes(
        pdf_path="lecture.pdf",
        output_dir="lecture_notes"
    )
    '''