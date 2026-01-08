License
This project is licensed under the MIT License - see the [MIT License](LICENSE) file for details.

This PowerShell script collects resource and configuration data from a Veeam Backup & Replication environment, 
including VMware Proxies, CDP Proxies, General Purpose Proxies, Gateways, Backup Servers, SQL Servers and Backup Repositories. It optionally performs a rescan of all hosts to ensure data is current.

The script aggregates hardware resources (CPU, RAM), calculates recommended concurrent tasks based on roles, and identifies multi-role servers. 

Results are categorized as optimized, underconfigured, or suboptimal configurations, with detailed comparisons. All findings are exported to CSV files for further analysis.

#USAGE
Open PowerShell on your Veeam Backup & Replication server.
Run the script:
.\your-script-name.ps1

Follow the prompt to choose whether to rescan all hosts.

Review the output in your console and check the generated CSV files in C:\csv\ for detailed results on repositories, proxies, gateways, and configuration analysis. 
