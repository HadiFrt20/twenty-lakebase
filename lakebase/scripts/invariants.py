"""Row counts per workspace schema for core CRM objects, to prove an upgrade lost no data.

  invariants.py snapshot <out.json>        (reads PG_DATABASE_URL)
  invariants.py compare <before> <after>   exit 1 if any count dropped
"""
import json, os, sys

TABLES = ("person", "company", "opportunity", "note", "task")


def snapshot(path):
    import psycopg

    counts = {}
    with psycopg.connect(os.environ["PG_DATABASE_URL"]) as conn:
        schemas = [r[0] for r in conn.execute("SELECT nspname FROM pg_namespace WHERE nspname LIKE 'workspace\\_%' ORDER BY 1")]
        for schema in schemas:
            for table in TABLES:
                exists = conn.execute("SELECT to_regclass(%s)", (f'"{schema}"."{table}"',)).fetchone()[0]
                if exists:
                    counts[f"{schema}.{table}"] = conn.execute(f'SELECT count(*) FROM "{schema}"."{table}"').fetchone()[0]
    json.dump(counts, open(path, "w"), indent=1, sort_keys=True)
    print(f"{len(schemas)} workspaces, {sum(counts.values())} rows across {len(counts)} tables")


def compare(before_path, after_path):
    before, after = json.load(open(before_path)), json.load(open(after_path))
    dropped = {k: (v, after.get(k)) for k, v in before.items() if after.get(k, -1) < v}
    for key, (was, now) in dropped.items():
        print(f"FAIL {key}: {was} -> {now}")
    print(f"{len(before) - len(dropped)}/{len(before)} tables kept their rows")
    sys.exit(1 if dropped else 0)


if __name__ == "__main__":
    {"snapshot": lambda: snapshot(sys.argv[2]), "compare": lambda: compare(sys.argv[2], sys.argv[3])}[sys.argv[1]]()
