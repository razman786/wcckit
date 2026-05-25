# opti_disk Workflow

The opti_disk area contains shell scripts and fio workloads for controlled disk and CPU-setting experiments:

- `opti_disk/set_nvme.sh`
- `opti_disk/config_nvme_queues.sh`
- `opti_disk/set_cpu_mode.sh`
- `opti_disk/reset_cpu_mode.sh`
- `opti_disk/fio_scripts/run_fio.sh`
- fio job files under `opti_disk/fio_scripts/`

Use dry-run modes where available. Confirm target device paths explicitly. Keep results separate from pipeline profiling runs so disk setup cost is not confused with pipeline runtime.

The purpose is to explore storage settings for radio-astronomy style processing pipelines, not to replace the main WCCKIT viewer/collector workflow.
