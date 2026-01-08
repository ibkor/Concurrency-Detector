License
This project is licensed under the MIT License - see the LICENSE file for details.

This PowerShell script collects resource and configuration data from a Veeam Backup & Replication environment, 
including VMware Proxies, CDP Proxies, NAS Gateways, and Backup Repositories. It optionally performs a rescan of all hosts to ensure data is current.

The script aggregates hardware resources (CPU, RAM), calculates recommended concurrent tasks based on roles, and identifies multi-role servers. 

Results are categorized as optimized, underconfigured, or suboptimal configurations, with detailed comparisons. All findings are exported to CSV files for further analysis.

