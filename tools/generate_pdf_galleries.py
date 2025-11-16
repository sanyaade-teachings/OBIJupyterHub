#!/usr/bin/env python3
"""Generate lightweight HTML galleries for PDF files within PAGES_DIR."""
from __future__ import annotations

import html
import os
import re
from pathlib import Path
from typing import Iterable, List, Tuple
from urllib.parse import quote

SCRIPT_DIR = Path(__file__).resolve().parent
PAGES_DIR = (SCRIPT_DIR / ".." / "jupyterhub_volumes" / "web" / "pages").resolve()

GALLERY_TEMPLATE = """<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{title}</title>
  <style>
    :root {{
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #222;
      background: #f8f8f8;
    }}
    body {{
      margin: 2rem;
    }}
    h1 {{
      font-size: 1.4rem;
      margin-bottom: 1rem;
    }}
    .gallery {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 1rem;
    }}
    .pdf-card {{
      background: #fff;
      border-radius: 8px;
      padding: 0.75rem;
      text-decoration: none;
      color: inherit;
      box-shadow: 0 1px 4px rgb(15 15 15 / 12%);
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.5rem;
    }}
    .pdf-card:hover {{
      box-shadow: 0 4px 12px rgb(15 15 15 / 18%);
    }}
    .pdf-card object {{
      width: 150px;
      height: 200px;
      border: 1px solid #ddd;
      border-radius: 4px;
      background: #fafafa;
      pointer-events: none;
    }}
    .pdf-fallback {{
      width: 100%;
      height: 100%;
      font-size: 0.8rem;
      color: #777;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      padding: 0.5rem;
      text-align: center;
    }}
    .pdf-label {{
      font-weight: 500;
      text-align: center;
    }}
  </style>
</head>
<body>
  <h1>{title}</h1>
  <div class="gallery">
{cards}
  </div>
</body>
</html>
"""

ITEM_TEMPLATE = """    <a class="pdf-card" href="{link_href}" target="_blank" rel="noopener">
      <object data="{object_src}" type="application/pdf" aria-label="{label}">
        <div class="pdf-fallback">
          <span>{label}</span>
          <small>Prévisualisation indisponible</small>
        </div>
      </object>
      <span class="pdf-label">{label}</span>
    </a>"""


def clean_label(entry_name: str) -> str:
    """Remove numeric prefixes and make a readable label."""
    base = Path(entry_name).stem
    base = re.sub(r"^\d+[_\-\s]*", "", base)
    base = base.replace("_", " ").replace("-", " ")
    base = re.sub(r"\s+", " ", base).strip()
    return base.capitalize() if base else Path(entry_name).stem


def should_skip_dir(dirname: str) -> bool:
    """Return True if we should ignore the directory while walking."""
    return dirname.startswith(".") or dirname.endswith("libs") or dirname == "__pycache__"


def iter_pdf_directories(root: Path) -> Iterable[Tuple[Path, List[str]]]:
    """Yield directories in root containing at least one PDF file."""
    for current_dir, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if not should_skip_dir(name)]
        pdfs = sorted(name for name in filenames if name.lower().endswith(".pdf"))
        if pdfs:
            yield Path(current_dir), pdfs


def directory_label(directory: Path) -> str:
    """Return a human-readable label for the given directory."""
    try:
        relative = directory.relative_to(PAGES_DIR)
    except ValueError:
        relative = directory
    if not relative.parts:
        return "Documents"
    return " / ".join(clean_label(part) for part in relative.parts)


def build_gallery_html(directory: Path, pdf_files: List[str]) -> str:
    """Create the HTML content for all PDFs in the directory."""
    cards = []
    for filename in pdf_files:
        label = html.escape(clean_label(filename))
        href = quote(filename)
        object_src = f"{href}#page=1&view=Fit"
        cards.append(
            ITEM_TEMPLATE.format(
                link_href=html.escape(href, quote=True),
                object_src=html.escape(object_src, quote=True),
                label=label,
            )
        )
    title = html.escape(directory_label(directory))
    return GALLERY_TEMPLATE.format(title=title, cards="\n".join(cards))


def main() -> None:
    if not PAGES_DIR.exists():
        raise SystemExit(f"❌ PAGES_DIR inexistant: {PAGES_DIR}")

    generated = 0
    for directory, pdf_files in iter_pdf_directories(PAGES_DIR):
        html_content = build_gallery_html(directory, pdf_files)
        output_path = directory / "documents.html"
        output_path.write_text(html_content, encoding="utf-8")
        rel_out = output_path.relative_to(PAGES_DIR)
        print(f"✅ {rel_out} ({len(pdf_files)} PDF)")
        generated += 1

    if not generated:
        print("ℹ️ Aucun PDF trouvé, aucun document.html généré.")


if __name__ == "__main__":
    main()
