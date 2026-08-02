#!/usr/bin/env python3
"""
drift-check.py: Deterministic drift measurement between code and documentation.

Compares API routes and database tables found in code against what is
documented in your vault/knowledge base. Reports undocumented elements.

This implementation is deterministic: same input, same output.

Usage:
  drift-check.py                  -> Write report + JSON to stdout
  drift-check.py --json           -> JSON only
  drift-check.py <app-name>       -> Single app
  drift-check.py --config <file>  -> Use custom config file

Configuration:
  Set AUTONOMIE_DRIFT_CONFIG env var or pass --config to point to a JSON file:
  {
    "vault_dir": "/path/to/vault",
    "apps": {
      "my-app": {
        "repo": "/path/to/repo",
        "doc": "/path/to/vault/DOMAIN_MODEL.md"
      }
    }
  }
"""
import json
import os
import re
import sys


def load_config():
    """Load configuration from file or environment."""
    config_path = None
    for i, arg in enumerate(sys.argv[1:]):
        if arg == "--config" and i + 2 < len(sys.argv):
            config_path = sys.argv[i + 2]
            break

    if not config_path:
        config_path = os.environ.get("AUTONOMIE_DRIFT_CONFIG", "")

    if not config_path:
        # Try default location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        config_path = os.path.join(script_dir, "..", "..", "drift-config.json")

    if os.path.isfile(config_path):
        with open(config_path) as f:
            return json.load(f)

    return {"vault_dir": os.environ.get("VAULT_DIR", os.path.expanduser("~/vault")), "apps": {}}


SKIP_DIRS = {"node_modules", ".next", ".git", "dist", "build", "coverage", ".turbo", ".cache"}
CODE_EXT = {".ts", ".tsx", ".js", ".jsx", ".mjs", ".sql"}

# Column names and SQL functions that look like table names
NO_TABLE = {
    "created_at", "updated_at", "deleted_at", "started_at", "ended_at", "expires_at",
    "published_at", "sent_at", "read_at", "last_login", "last_seen", "is_active",
    "is_admin", "is_deleted", "is_verified", "full_name", "first_name", "last_name",
    "display_name", "file_path", "file_name", "file_type", "file_size", "content_type",
    "mime_type", "status_code", "error_message", "row_number", "date_trunc",
    "json_build_object", "json_agg", "array_agg", "string_agg", "generate_series",
    "information_schema",
}

TRIVIAL_GROUPS = {"health", "auth", "cron", "webhook", "storage", "upload", "api"}

TABLE_RE = re.compile(
    r"(?:FROM|INTO|UPDATE|JOIN|DELETE\s+FROM)\s+[\"`']?([a-z][a-z0-9_]+)[\"`']?"
)


def code_files(root):
    """All code files under root, in stable order."""
    hits = []
    for folder, subdirs, names in os.walk(root):
        subdirs[:] = sorted(d for d in subdirs if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(names):
            if os.path.splitext(name)[1] in CODE_EXT:
                hits.append(os.path.join(folder, name))
    return hits


def route_groups(repo):
    """Top-level groups of API routes, e.g. /api/members/... -> members."""
    groups = set()
    for base in (os.path.join(repo, "src", "app", "api"), os.path.join(repo, "app", "api")):
        if not os.path.isdir(base):
            continue
        for folder, subdirs, names in os.walk(base):
            subdirs[:] = sorted(d for d in subdirs if d not in SKIP_DIRS)
            if any(n in ("route.ts", "route.js", "route.tsx") for n in names):
                rel = os.path.relpath(folder, base)
                if rel == ".":
                    continue
                group = rel.split(os.sep)[0].lower()
                if group.startswith("[") or group in TRIVIAL_GROUPS:
                    continue
                groups.add(group)
    return groups


def tables(repo):
    """Table names from SQL-like expressions in code."""
    found = set()
    for part in ("src", "lib", "app"):
        root = os.path.join(repo, part)
        if not os.path.isdir(root):
            continue
        for path in code_files(root):
            try:
                with open(path, encoding="utf-8", errors="ignore") as fh:
                    content = fh.read()
            except OSError:
                continue
            for match in TABLE_RE.findall(content):
                if "_" in match and match not in NO_TABLE:
                    found.add(match)
    return found


def missing(terms, doc_text):
    """Terms that do not appear as standalone words in the document."""
    result = []
    for term in sorted(terms):
        if not re.search(r"(?<![a-z0-9_])" + re.escape(term) + r"(?![a-z0-9_])", doc_text):
            result.append(term)
    return result


def main():
    config = load_config()
    vault_dir = config.get("vault_dir", os.environ.get("VAULT_DIR", os.path.expanduser("~/vault")))
    apps = config.get("apps", {})

    json_only = "--json" in sys.argv
    explicit = [a for a in sys.argv[1:] if not a.startswith("--") and a != sys.argv[0]]
    # Remove --config value from explicit list
    for i, a in enumerate(sys.argv[1:]):
        if a == "--config":
            if i + 2 < len(sys.argv):
                val = sys.argv[i + 2]
                if val in explicit:
                    explicit.remove(val)
            break

    selection = explicit or sorted(apps)

    result = {"apps": {}, "missing_total": 0, "no_document": []}

    for app in selection:
        if app not in apps:
            continue
        repo = apps[app].get("repo", "")
        doc = apps[app].get("doc", "")
        if not os.path.isdir(repo):
            continue
        if not os.path.isfile(doc):
            result["no_document"].append({"app": app, "doc": doc})
            continue
        text = open(doc, encoding="utf-8", errors="ignore").read().lower()
        open_routes = missing(route_groups(repo), text)
        open_tables = missing(tables(repo), text)
        result["apps"][app] = {
            "doc": doc,
            "routes": open_routes,
            "tables": open_tables,
        }
        result["missing_total"] += len(open_routes) + len(open_tables)

    if not json_only:
        report_path = os.path.join(vault_dir, "autonomie", "DRIFT_REPORT.md")
        os.makedirs(os.path.dirname(report_path), exist_ok=True)
        lines = [
            "---", 'title: "Drift Measurement (deterministic)"', "type: generated",
            "status: current", "---", "",
            "# Drift Between Code and Documentation",
            "",
            "> Generated by `drift-check.py`.",
            "",
            f"**Missing entries total: {result['missing_total']}**",
            "",
        ]
        for app, data in sorted(result["apps"].items()):
            if not data["routes"] and not data["tables"]:
                continue
            lines += [f"## {app}", "", f"Document: `{data['doc']}`", ""]
            if data["routes"]:
                lines += [f"Missing API areas ({len(data['routes'])}):", ""]
                lines += [f"- `/api/{r}/`" for r in data["routes"]] + [""]
            if data["tables"]:
                lines += [f"Missing tables ({len(data['tables'])}):", ""]
                lines += [f"- `{t}`" for t in data["tables"]] + [""]
        if result["no_document"]:
            lines += ["## Apps without domain model", ""]
            lines += [f"- {e['app']}: `{e['doc']}` missing" for e in result["no_document"]] + [""]
        open(report_path, "w", encoding="utf-8").write("\n".join(lines))

    print(json.dumps(result, ensure_ascii=False))
    return 1 if result["missing_total"] > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
