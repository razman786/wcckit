# Environment Variables

Common environment variables used by WCCKIT scripts include:

| Variable | Purpose |
| --- | --- |
| `WCCKIT_BASE_IMAGE` | Override base image tag for installer builds. |
| `WCCKIT_PROFILER_IMAGE` | Override BCC profiler image tag. |
| `WCCKIT_PIPELINE_IMAGE` | Override combined pipeline image tag. |
| `WCCKIT_INCLUDE_AMD_UPROF` | `auto`, `1`, or `0` for AMD uProf inclusion. |
| `WCCKIT_AMD_UPROF_DEB` | Path to AMD uProf `.deb`. |
| `WCCKIT_AMD_UPROF_URL` | AMD uProf download URL. |
| `WCCKIT_AMD_UPROF_MD5` | AMD uProf MD5 checksum. |
| `WCCKIT_INCLUDE_AMD_ESMI` | `1` or `0` for AMD e-smi inclusion. |
| `WCCKIT_AMD_ESMI_URL` | AMD e-smi `.deb` URL. |
| `WCCKIT_AMD_ESMI_SHA256` | AMD e-smi SHA256 checksum. |
| `WCCKIT_DEPLOYMENT_MODE` | `all`, `viewer`, or `collector`. |
| `WCCKIT_PCM_SENSOR_URL` | Viewer-side Intel PCM sensor endpoint override. |
| `WCCKIT_ESMI_TOOL` | Path to mounted host e-smi tool inside collector. |

Script `--help` output is the authoritative source for current options.
