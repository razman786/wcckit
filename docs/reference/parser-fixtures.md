# Parser Fixtures And Compatibility Corpus

WCCKIT parsers are tested with small fixtures rather than live hardware in CI. This keeps CI deterministic and non-destructive, but it creates a known risk: external tools such as BCC, Intel PCM, AMD uProf, and e-smi can change their output between versions, CPU families, kernels, and privilege modes.

The mitigation is to maintain a small compatibility corpus of redacted real outputs. Each time WCCKIT is validated on a new compute-node class, promote representative raw output into `tests/fixtures/` and add or update parser tests.

## What To Capture

Prefer small samples that include:

- the header line;
- one or two valid data rows;
- one warning, unsupported, or malformed row when available;
- status output showing whether the tool was available;
- enough metadata to identify the tool version, CPU vendor, kernel, and distribution.

Do not commit whole `runs/` directories, private pipeline data, full command lines, user names, hostnames, IP addresses, or large logs.

## Fixture Promotion Helper

Use `scripts/collect_fixture_from_run.py` to copy known artifact paths from a run directory into a redacted fixture set:

```bash
python3 scripts/collect_fixture_from_run.py   --run runs/ddfacet-intel-001   --collector bpf-io   --output tests/fixtures/captured   --label bpf-io-ubuntu2404-bcc029-intel
```

The helper writes:

```text
tests/fixtures/captured/<label>/
  fixture.meta.json
  logs/...
  events/...
  metrics/...
```

It redacts common host-specific values, including IPv4 addresses, home-directory usernames, email addresses, temporary paths, the current hostname, and the current user name. Use `--redact-regex` for project-specific values:

```bash
python3 scripts/collect_fixture_from_run.py   --run runs/ddfacet-amd-001   --collector amd-uprof-pcm   --label amduprofpcm-5.3-zen4   --redact-regex 'private-project-[A-Za-z0-9_-]+'
```

The default per-file limit is 64 KiB. Use `--max-bytes` to keep fixtures smaller. Truncated files are marked with `WCCKIT_FIXTURE_TRUNCATED`, and the metadata records the original and fixture hashes.

## Supported Collector Names

The helper currently knows these collector groups:

| Collector | Typical files |
| --- | --- |
| `bpf-io` | BPF I/O logs, JSONL, and line protocol. |
| `app-uflow` | raw uflow log, parsed JSONL, folded stacks, and summary line protocol. |
| `app-ucalls` | parsed ucalls JSONL and summary line protocol. |
| `app-ustat` | parsed ustat JSONL and summary line protocol. |
| `amd-uprof-pcm` | AMDuProfPcm CPU CSV, JSONL, line protocol, and logs. |
| `amd-uprof-memory` | AMDuProfPcm memory CSV, JSONL, line protocol, and logs. |
| `amd-uprof-power` | AMDuProfPcm power CSV, JSONL, line protocol, and logs. |
| `amd-esmi-energy` | e-smi energy CSV, JSONL, line protocol, and logs. |
| `intel-pcm` | Intel PCM JSONL, line protocol, logs, and status. |
| `roofline` | AMD roofline status, line protocol, manifest, and logs. |
| `manifest` | run manifest only. |
| `all` | every known group above. |

## Metadata Policy

Each fixture set has `fixture.meta.json` with:

- source run directory;
- collector group;
- capture time;
- files copied;
- source and fixture sizes;
- source and fixture SHA-256 hashes;
- whether truncation occurred;
- whether automatic redaction changed the file.

For fixtures intended to be committed, review the metadata and file contents manually. The helper is a guardrail, not a substitute for judgement.

## Test Policy

When adding a new real fixture, update parser tests to check semantic behaviour rather than full byte-for-byte output. Prefer assertions such as:

- valid rows produce expected JSONL keys;
- unsupported output emits `available=false` or a collector-status point;
- line protocol uses the expected measurement;
- method names, stack frames, full paths, and commands do not become Influx tags;
- timestamp mapping keeps points within the run window where applicable.

CI should remain non-privileged. Live Intel PCM, AMD uProf, e-smi, BPF, and Pyroscope checks remain manual hardware tests.
