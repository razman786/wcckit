# opti_disk Safety

!!! danger "Destructive tooling"
    `opti_disk/` can destroy data or disrupt the host if used incorrectly. WCCKIT accepts no responsibility for data loss, downtime, hardware damage, or system disruption caused by misuse or incorrect device selection.

The opti_disk scripts may:

- format NVMe namespaces;
- rewrite GPT or partition tables;
- create filesystems;
- mount or unmount disks;
- write sysfs or kernel settings;
- change CPU governors;
- drop caches;
- configure NVMe queue parameters;
- run heavy `fio` workloads.

Only use these scripts on explicitly selected test devices. Do not run them on disks containing `/`, `/boot`, `/home`, swap, or any mounted partition. Use dry-run modes first and review the planned actions before confirming.

The normal WCCKIT pipeline profiler does not need opti_disk.
