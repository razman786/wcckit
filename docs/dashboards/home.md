# 00 WCCKIT Home

The Home dashboard is the Grafana landing page for the viewer stack.

Panels:

- **WCCKIT**: project identity and short orientation.
- **Viewer Stack**: local Grafana, InfluxDB, and Pyroscope endpoint reminders.
- **Dashboards**: links to the provisioned dashboards.
- **Links**: project and upstream tool references.
- **Run A Collector**: quick command reminders for starting an overview run.
- **InfluxDB Datasource**: whether Grafana can query the WCCKIT InfluxDB source.
- **Recent Run Markers**: count of recently written run start/end markers.
- **Collector Status Points**: count of collector status records.
- **PCM Scrape Samples**: count of Intel PCM scrape samples when the PCM bridge is active.

If the datasource panel is empty, check that the viewer stack is running and that InfluxDB was provisioned with the `wcckit` bucket and token.
