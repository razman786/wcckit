# CLI Tools

WCCKIT is mostly used through wrapper scripts, but the containers also include upstream profiling tools. These can be useful when Grafana is not needed or when validating a collector manually.

Start with:

```bash
dockerfiles/bin/run-wcckit-viewer.sh --help
dockerfiles/bin/run-wcckit-pipeline-overview.sh --help
dockerfiles/bin/run-wcckit-intel-overview.sh --help
dockerfiles/bin/run-wcckit-amd-overview.sh --help
```

For direct tool usage, see the Intel PCM, AMD uProf, and BCC pages.
