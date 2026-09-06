#!/usr/bin/env python3
"""
Image-to-RMarkdown Pipeline
============================
Converts sequential screenshots of R code into an .Rmd file using:
  1. Tesseract OCR for initial text extraction
  2. Claude Sonnet 4.6 for context-aware correction
  3. Line-number-based stitching with overlap detection

Usage:
  source .venv/bin/activate
  python scripts/image_to_rmd_pipeline.py [--image-dir PATH] [--output FILE]
"""

import os
import sys
import re
import json
import base64
import logging
import time
from pathlib import Path
from datetime import datetime

import argparse

import pytesseract
from PIL import Image
import anthropic

# ── Configuration ──────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_IMAGE_DIR = PROJECT_ROOT / "input_files" / "init_images"
DEFAULT_OUTPUT_FILE = PROJECT_ROOT / "orchestration_2.Rmd"
LOG_FILE = PROJECT_ROOT / "scripts" / "pipeline.log"
DISCREPANCY_FILE = PROJECT_ROOT / "scripts" / "discrepancies.log"
SECRETS_FILE = PROJECT_ROOT / "secrets" / "cluade_api.txt"  # note: typo in filename is intentional

MODEL = "claude-sonnet-4-6"
MAX_RETRIES = 2
RETRY_DELAY = 5  # seconds

# ── Logging Setup ─────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, mode="w"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger(__name__)

# ── Helper Functions ──────────────────────────────────────────────────────────


def load_api_key() -> str:
    """Load the Anthropic API key from the secrets file."""
    with open(SECRETS_FILE, "r") as f:
        key = f.readline().strip()
    if not key.startswith("sk-ant-"):
        raise ValueError("API key does not look valid (expected sk-ant-... prefix)")
    return key


def get_ordered_images(image_dir: Path) -> list[Path]:
    """Return image paths sorted by file creation time (birth time)."""
    images = list(image_dir.glob("*.jpeg")) + list(image_dir.glob("*.jpg"))
    # Sort by birth time (st_birthtime on macOS)
    images.sort(key=lambda p: p.stat().st_birthtime)
    log.info(f"Found {len(images)} images in {image_dir}, sorted by creation time")
    return images


def image_to_base64(image_path: Path) -> str:
    """Encode an image file to base64 string."""
    with open(image_path, "rb") as f:
        return base64.standard_b64encode(f.read()).decode("utf-8")


def run_tesseract(image_path: Path) -> str:
    """Run Tesseract OCR on an image and return raw text."""
    try:
        img = Image.open(image_path)
        # Use config for better code recognition
        custom_config = r"--oem 3 --psm 6"
        text = pytesseract.image_to_string(img, config=custom_config)
        return text
    except Exception as e:
        log.warning(f"Tesseract failed on {image_path.name}: {e}")
        return ""


def build_claude_prompt(ocr_text: str, previous_context: str, image_index: int, total_images: int, is_r_script: bool = False) -> str:
    """Build the correction prompt for Claude Vision."""
    file_type = "R script" if is_r_script else "R Markdown"
    chunk_rule = "" if is_r_script else "\n5. Include R Markdown chunk delimiters (```{{r}} and ```) exactly as they appear."

    prompt = f"""You are transcribing {file_type} code from a screenshot of an RStudio editor.

IMAGE {image_index + 1} of {total_images}.

RULES — follow these strictly:
1. Transcribe EXACTLY what is visible on screen. Do NOT interpret, infer, or complete code.
2. Preserve every character exactly: spacing, indentation, comments, blank lines.
3. Each line MUST be prefixed with its line number as shown in the editor's left margin, followed by a pipe: e.g. "42| code here"
4. If a line number is not visible or cut off, estimate it based on surrounding numbers and mark with ~: e.g. "~43| code here"{chunk_rule}
6. If you cannot read a character or word clearly, use [UNCLEAR] as a placeholder.
7. Do NOT add any commentary, explanation, or markdown formatting around your output.
8. Output ONLY the numbered lines of code, nothing else.

Below is a Tesseract OCR attempt at this image. It will contain errors — use it as a starting point, but trust what you SEE in the image over what the OCR says.

--- TESSERACT OCR OUTPUT ---
{ocr_text if ocr_text else "[Tesseract failed — transcribe directly from the image]"}
--- END OCR OUTPUT ---
"""

    if previous_context:
        # Include last ~15 lines from previous image for continuity
        prev_lines = previous_context.strip().split("\n")
        tail = "\n".join(prev_lines[-15:])
        prompt += f"""
--- PREVIOUS IMAGE CONTEXT (last lines) ---
{tail}
--- END PREVIOUS CONTEXT ---

Use this context to understand variable names, function names, and coding patterns that may help resolve ambiguous characters in the current image. But do NOT repeat these lines — only transcribe what is in the CURRENT image.
"""

    return prompt


def call_claude_vision(
    client: anthropic.Anthropic,
    image_path: Path,
    prompt: str,
) -> str:
    """Send image + prompt to Claude Vision and return the corrected text."""
    img_b64 = image_to_base64(image_path)

    # Determine media type
    suffix = image_path.suffix.lower()
    media_type = "image/jpeg"  # all our files are .jpeg

    response = client.messages.create(
        model=MODEL,
        max_tokens=8192,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": img_b64,
                        },
                    },
                    {
                        "type": "text",
                        "text": prompt,
                    },
                ],
            }
        ],
    )

    return response.content[0].text


def process_image(
    client: anthropic.Anthropic,
    image_path: Path,
    image_index: int,
    total_images: int,
    previous_context: str,
    is_r_script: bool = False,
) -> str:
    """Process a single image through Tesseract + Claude correction pipeline."""

    # Step 1: Tesseract OCR
    log.info(f"  [1/2] Running Tesseract on {image_path.name}...")
    ocr_text = run_tesseract(image_path)
    ocr_line_count = len(ocr_text.strip().split("\n")) if ocr_text.strip() else 0
    log.info(f"  [1/2] Tesseract extracted {ocr_line_count} lines")

    # Step 2: Claude Vision correction
    prompt = build_claude_prompt(ocr_text, previous_context, image_index, total_images, is_r_script)

    for attempt in range(MAX_RETRIES + 1):
        try:
            log.info(f"  [2/2] Sending to Claude (attempt {attempt + 1})...")
            corrected = call_claude_vision(client, image_path, prompt)
            corrected_line_count = len(corrected.strip().split("\n"))
            log.info(f"  [2/2] Claude returned {corrected_line_count} lines")
            return corrected
        except Exception as e:
            log.warning(f"  [2/2] Claude failed (attempt {attempt + 1}): {e}")
            if attempt < MAX_RETRIES:
                log.info(f"  Retrying in {RETRY_DELAY}s...")
                time.sleep(RETRY_DELAY)
            else:
                # If Claude fails completely and we have OCR text, return that
                if ocr_text.strip():
                    log.warning(f"  Falling back to raw Tesseract output")
                    return ocr_text
                else:
                    log.error(f"  SKIPPING image {image_path.name} — both Tesseract and Claude failed")
                    return ""


# ── Line Number Parsing ───────────────────────────────────────────────────────


def parse_numbered_lines(text: str) -> list[tuple[int, str, bool]]:
    """
    Parse lines with number prefixes into (line_number, content, is_estimated).

    Handles formats like:
      "42| code here"       -> (42, " code here", False)
      "~43| code here"      -> (43, " code here", True)
      " 103| code here"     -> (103, " code here", False)
    """
    results = []
    for raw_line in text.split("\n"):
        # Match: optional ~, optional spaces, digits, pipe, rest
        m = re.match(r"^(~?)\s*(\d+)\s*\|\s?(.*)", raw_line)
        if m:
            is_estimated = m.group(1) == "~"
            line_num = int(m.group(2))
            content = m.group(3)
            results.append((line_num, content, is_estimated))
        # Also try without pipe (sometimes OCR/Claude may use other delimiters)
        else:
            m2 = re.match(r"^(~?)\s*(\d+)\s*[|:]\s?(.*)", raw_line)
            if m2:
                is_estimated = m2.group(1) == "~"
                line_num = int(m2.group(2))
                content = m2.group(3)
                results.append((line_num, content, is_estimated))
    return results


# ── Overlap Detection and Merging ─────────────────────────────────────────────


def detect_and_merge_overlap(
    prev_lines: list[tuple[int, str, bool]],
    curr_lines: list[tuple[int, str, bool]],
    discrepancy_log: list[str],
    prev_image_name: str,
    curr_image_name: str,
) -> list[tuple[int, str, bool]]:
    """
    Merge two sets of numbered lines, handling overlaps.

    For overlapping line numbers:
    - If both versions agree: keep one
    - If they differ: flag discrepancy, prefer the version from the image
      where the line appears closer to the top (= curr_lines, since overlap
      lines are at the bottom of prev and top of curr)
    """
    if not prev_lines:
        return curr_lines
    if not curr_lines:
        return prev_lines

    prev_dict = {num: (content, est) for num, content, est in prev_lines}
    curr_dict = {num: (content, est) for num, content, est in curr_lines}

    prev_max = max(prev_dict.keys())
    curr_min = min(curr_dict.keys())

    overlap_start = curr_min
    overlap_end = prev_max

    if overlap_start <= overlap_end:
        overlap_nums = range(overlap_start, overlap_end + 1)
        log.info(f"  Overlap detected: lines {overlap_start}-{overlap_end}")

        for num in overlap_nums:
            if num in prev_dict and num in curr_dict:
                prev_content, prev_est = prev_dict[num]
                curr_content, curr_est = curr_dict[num]

                if prev_content.strip() != curr_content.strip():
                    msg = (
                        f"DISCREPANCY at line {num} "
                        f"(between {prev_image_name} and {curr_image_name}):\n"
                        f"  Version A (prev img): {prev_content!r}\n"
                        f"  Version B (curr img): {curr_content!r}\n"
                        f"  KEPT: Version B (curr img — line appears near top)\n"
                    )
                    discrepancy_log.append(msg)
                    log.warning(f"  Discrepancy at line {num} — keeping curr image version")

    # Build merged result: prev lines up to (but not including) overlap, then all curr lines
    merged = []
    for num, content, est in prev_lines:
        if num < curr_min:
            merged.append((num, content, est))

    merged.extend(curr_lines)
    return merged


# ── Post-Processing ───────────────────────────────────────────────────────────


def validate_chunk_boundaries(lines: list[str]) -> list[str]:
    """Check that every ```{r...} has a matching ```. Return list of warnings."""
    warnings = []
    open_count = 0
    open_line = None

    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        if re.match(r"^```\{r", stripped):
            if open_count > 0:
                warnings.append(
                    f"Line {i}: Opening chunk ```{{r}} found while previous chunk "
                    f"(opened at line {open_line}) is still open"
                )
            open_count += 1
            open_line = i
        elif stripped == "```" and open_count > 0:
            open_count -= 1
            open_line = None

    if open_count > 0:
        warnings.append(f"Unclosed code chunk (last opened at line {open_line})")

    return warnings


# ── Main Pipeline ─────────────────────────────────────────────────────────────


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Convert screenshots of R code into an output file.")
    parser.add_argument("--image-dir", type=Path, default=DEFAULT_IMAGE_DIR,
                        help="Directory containing input screenshot images")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT_FILE,
                        help="Output file path (e.g. scripts/pull_apps.R or orchestration_2.Rmd)")
    return parser.parse_args()


def main():
    args = parse_args()
    image_dir = args.image_dir.resolve()
    output_file = args.output.resolve()
    is_r_script = output_file.suffix.lower() == ".r"

    log.info("=" * 70)
    log.info(f"Image-to-{'R Script' if is_r_script else 'RMarkdown'} Pipeline")
    log.info(f"  Image dir:   {image_dir}")
    log.info(f"  Output file: {output_file}")
    log.info("=" * 70)

    # Load API key
    api_key = load_api_key()
    client = anthropic.Anthropic(api_key=api_key)
    log.info("API client initialized")

    # Get ordered images
    images = get_ordered_images(image_dir)
    if not images:
        log.error("No images found in input directory!")
        sys.exit(1)

    # Process each image
    all_parsed_lines: list[tuple[int, str, bool]] = []
    previous_context = ""
    discrepancy_log: list[str] = []
    skipped_images: list[str] = []

    for i, image_path in enumerate(images):
        log.info(f"\n{'─' * 60}")
        log.info(f"Processing image {i + 1}/{len(images)}: {image_path.name}")
        log.info(f"{'─' * 60}")

        corrected_text = process_image(
            client=client,
            image_path=image_path,
            image_index=i,
            total_images=len(images),
            previous_context=previous_context,
            is_r_script=is_r_script,
        )

        if not corrected_text.strip():
            skipped_images.append(image_path.name)
            log.error(f"  No output for {image_path.name} — skipped")
            continue

        # Parse numbered lines
        parsed = parse_numbered_lines(corrected_text)
        if not parsed:
            log.warning(
                f"  Could not parse any numbered lines from Claude output. "
                f"Storing raw text as fallback."
            )
            # Store raw lines with estimated line numbers
            raw_lines = corrected_text.strip().split("\n")
            last_num = all_parsed_lines[-1][0] if all_parsed_lines else 0
            parsed = [(last_num + j + 1, line, True) for j, line in enumerate(raw_lines)]

        # Merge with overlap detection
        line_range = f"{parsed[0][0]}-{parsed[-1][0]}" if parsed else "empty"
        log.info(f"  Parsed {len(parsed)} lines (range: {line_range})")

        prev_image_name = images[i - 1].name if i > 0 else ""
        all_parsed_lines = detect_and_merge_overlap(
            all_parsed_lines,
            parsed,
            discrepancy_log,
            prev_image_name,
            image_path.name,
        )

        # Update context for next iteration
        previous_context = corrected_text

        log.info(f"  Total accumulated lines: {len(all_parsed_lines)}")

    # ── Post-processing ───────────────────────────────────────────────────

    log.info(f"\n{'=' * 70}")
    log.info("Post-processing")
    log.info(f"{'=' * 70}")

    # Sort by line number and extract content
    all_parsed_lines.sort(key=lambda x: x[0])
    final_lines = [content for _, content, _ in all_parsed_lines]

    log.info(f"Total lines in final output: {len(final_lines)}")

    # Validate chunk boundaries (Rmd only)
    chunk_warnings = []
    if not is_r_script:
        chunk_warnings = validate_chunk_boundaries(final_lines)
        if chunk_warnings:
            log.warning("Chunk boundary issues found:")
            for w in chunk_warnings:
                log.warning(f"  {w}")
        else:
            log.info("Chunk boundary validation: OK")
    else:
        log.info("Chunk boundary validation: skipped (R script output)")

    # Ensure output directory exists
    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Write output file
    with open(output_file, "w") as f:
        f.write("\n".join(final_lines))
        f.write("\n")

    log.info(f"Output written to: {output_file}")

    # Write discrepancy log
    if discrepancy_log:
        with open(DISCREPANCY_FILE, "w") as f:
            f.write(f"Discrepancy Report — {datetime.now().isoformat()}\n")
            f.write(f"{'=' * 60}\n\n")
            for entry in discrepancy_log:
                f.write(entry + "\n")
        log.warning(f"{len(discrepancy_log)} discrepancies logged to: {DISCREPANCY_FILE}")
    else:
        log.info("No discrepancies found between overlapping images")

    # Summary
    log.info(f"\n{'=' * 70}")
    log.info("Pipeline Summary")
    log.info(f"{'=' * 70}")
    log.info(f"  Images processed: {len(images) - len(skipped_images)}/{len(images)}")
    log.info(f"  Images skipped:   {len(skipped_images)}")
    log.info(f"  Total lines:      {len(final_lines)}")
    log.info(f"  Discrepancies:    {len(discrepancy_log)}")
    log.info(f"  Chunk warnings:   {len(chunk_warnings)}")
    if skipped_images:
        log.info(f"  Skipped images:   {', '.join(skipped_images)}")
    log.info(f"  Output file:      {output_file}")


if __name__ == "__main__":
    main()
