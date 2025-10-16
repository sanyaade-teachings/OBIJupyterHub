#!/usr/bin/env python3
import os
import re
import json

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PAGES_DIR = os.path.join(SCRIPT_DIR,"..","jupyterhub_volumes","web","pages")

def clean_label(filename):
    """Nettoie les préfixes numériques et formate un label lisible."""
    name = os.path.splitext(os.path.basename(filename))[0]
    name = re.sub(r'^\d+_', '', name)  # Supprime "00_", "01_", etc.
    name = name.replace("_", " ")
    return name.capitalize()

def build_tree(directory):
    """Construit récursivement la structure de menu à partir du répertoire donné."""
    entries = []

    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)

        # Ignorer les répertoires cachés ou ceux finissant par 'libs'
        if os.path.isdir(path):
            if name.endswith("libs") or name.startswith("."):
                continue

            children = build_tree(path)
            if children:
                entries.append({
                    "label": clean_label(name),
                    "children": children
                })

        elif name.endswith(".html"):
            entries.append({
                "file": os.path.relpath(path, PAGES_DIR).replace("\\", "/"),
                "label": clean_label(name)
            })

    return entries

def count_pages(tree):
    """Compte le nombre total de fichiers HTML dans l'arborescence."""
    total = 0
    for node in tree:
        if "file" in node:
            total += 1
        if "children" in node:
            total += count_pages(node["children"])
    return total

if __name__ == "__main__":
    tree = build_tree(PAGES_DIR)
    output_path = os.path.join(PAGES_DIR, "pages.json")

    with open(output_path, "w", encoding="utf-8") as out:
        json.dump(tree, out, indent=2, ensure_ascii=False)

    print(f"✅ Generated {output_path} with {count_pages(tree)} HTML pages.")
