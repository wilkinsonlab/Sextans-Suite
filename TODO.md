# TODO

Lightweight backlog for things noticed but not yet acted on, so they don't get lost.

## Sextans Fix

- **Recommend/enforce deletion of processed CSV and RDF files after a successful load.**
  Raised during a pentest session (2026-09-09): `Sextans-Fix/data` holds the source CSV and the
  generated `triples/*.nq` output at rest for as long as the operator leaves them there, and the
  folder is intentionally world-readable/writable (`chmod -R o+rwX`, needed so the fixed-UID
  `cde-box-daemon`/`yarrrml-rdfizer` containers can read/write it). `Fix-install/README.md` now
  recommends deleting these files once data is confirmed loaded into Virtuoso, but nothing
  enforces or automates it yet. Consider: an optional cleanup step in `t.rb`/`transform-cdev2.rb`
  after a confirmed-successful write, or a documented cron/manual habit -- decide once there's a
  concrete need.

- **Clean up per-type scratch directories in `yarrrml-rdfizer`.** Explicitly deferred (2026-09-09)
  when per-type isolation was added (each type now gets its own `/mnt/data/<type>/{tmp,triples}`,
  including the smoke test's own `_smoketest` type and every custom datatype) -- old chunk files
  in each type's `tmp/` get wiped at the *start* of that type's next run, but nothing removes a
  type's directory entirely if that type stops being used (e.g. a custom datatype gets removed,
  or renamed). Not urgent -- these are small text files -- but worth a real answer once the number
  of custom types in active use grows.
