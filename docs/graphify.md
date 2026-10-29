# Knowledge graph: building and refreshing

graphify turns repositories into a queryable graph. It has two layers, and they
cost very differently:

- **Code layer**: entities and references parsed from the files graphify
  understands. No LLM, no network, about a second per repository.
- **Document layer**: concepts and rationale read out of READMEs, ADRs and
  agent instructions by an LLM. Over several repositories a full build runs to
  hundreds of thousands of input tokens; an incremental one costs only what
  changed.

Coverage of the code layer depends on the repository. Some come out detailed,
others nearly empty until the LLM pass runs. Build it, then check what came out
before relying on it.

## One repository, no LLM

```bash
cd <repository>
graphify update . --no-cluster                  # code layer
graphify cluster-only . --no-label --no-viz     # communities, unnamed
```

The result lands in `graphify-out/`. Every query runs offline against it:

```bash
graphify affected "<node>"            # what references it, with file:line
graphify god-nodes                    # the most connected nodes
graphify explain "<node>"             # a node and its neighbours
graphify path "<node A>" "<node B>"   # shortest path between two nodes
graphify query "<question>" --budget 1500
```

`affected` is the one to reach for before changing something shared: it lists
every consumer with the line that references it.

## Several repositories in one graph

Check the repositories out side by side and build from their shared parent
directory. graphify keys every file by its path relative to that directory, so
the same layout is needed every time the graph is refreshed.

Keep the result somewhere versioned (a docs repository works), and commit
three things with it that the graph files alone do not carry:

- **`.graphifyignore`**: the scope. The parent directory usually holds more
  than the graph should cover: other repositories, worktrees, backups. Without
  the ignore file the next refresh pulls them all in.
- **`.graphify_labels.json`**: the community names. They exist only in the
  working `graphify-out/`. A refresh that starts from the committed graph files
  without it comes back with "Community N" placeholders, and naming them again
  costs LLM calls.
- **`cache/`** and **`manifest.json`**: per-file hashes and extraction results.
  They are what makes a refresh incremental.

If that versioned copy lives inside one of the repositories in scope, list its
directory in `.graphifyignore` as well. Otherwise every refresh reads the
previous graph back in as documents, and its manifest alone turns into hundreds
of nodes. The first build does not show the problem, because the copy does not
exist yet; the first refresh after publishing does.

## Refreshing a shared graph

```bash
cd <parent directory>

# 0. Back up the working graph: it may be the only copy of the community names.
cp -r graphify-out "graphify-out.bak-$(date +%F)"

# 1. Bring every repository in scope up to date.
for r in <repository> <repository> ...; do
  git -C "$r" pull --ff-only
done

# 2. Restore the scope from the committed copy, or write it if it was never
#    recorded: one line per directory to leave out.
cp <graph home>/.graphifyignore .
#    Make sure it also excludes worktrees and the backup from step 0,
#    e.g. ".wt-*/" and "*.bak-*/".

# 3. Code layer: no LLM, free.
graphify update .
```

Compare the node and edge counts step 3 prints with the previous build, and
look at where the nodes come from before going further:

```bash
python3 -c "import json,collections as c; n=json.load(open('graphify-out/graph.json'))['nodes']; [print(v,k) for k,v in c.Counter(str(x.get('source_file','')).split('/')[0] for x in n).most_common()]"
```

A result close to the previous build is expected. A jump means something
entered the scope that should not have: another repository, a worktree, or the
graph's own published copy. Fix `.graphifyignore` and rerun step 3 before
paying for step 4. `update` refuses to overwrite a graph with one that has
fewer nodes, so a corrected rerun needs `--force`.

```text
# 4. Document layer: in a Claude Code session started in the parent directory
/graphify . --update
```

Step 4 re-reads through the LLM only the files whose hash changed since the
last build, so its cost follows how much documentation moved.

```bash
# 5. Only if GRAPH_REPORT.md now shows "Community N" placeholders.
graphify label . --missing-only

# 6. Back into the committed copy.
K=<graph home>
cp graphify-out/{graph.json,GRAPH_REPORT.md,graph.html,manifest.json,.graphify_labels.json} "$K/"
cp -r graphify-out/cache "$K/"
cp .graphifyignore "$K/"
```

Then update the build date and the node and edge counts wherever the graph is
described, and commit on a branch.
