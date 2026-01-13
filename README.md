#LICENSE

This project is licensed under the MIT License - see the [MIT License](LICENSE) file for details.

SUMMARY

In many Veeam environments, it is common for servers to be assigned multiple roles, such as proxies, gateways, repositories, or backup servers without a thorough analysis of their available resources and the number of concurrent tasks they are configured to handle. This frequently leads to resource bottlenecks, performance issues, or errors, particularly in larger environments where it becomes challenging to maintain a comprehensive view of all servers, their hardware resources, assigned roles, and concurrent task settings. 

This script was developed to address these challenges and simplify the optimization of Veeam environments. By providing a consolidated overview of the backup infrastructure, the script helps to easily identify potential resource issues and make informed decisions regarding configuration and resource planning on the backup servers.

While this script may not be highly professional, I created it with the intention of making our work and that of our colleagues a bit easier. Feedback and suggestions are always welcome!

DESCRIPTION

There are two dedicated PowerShell scripts available for analyzing concurrency in Veeam installations:

ConcurrencyInspectorWindows.ps1:
Designed for Windows environments, this script is compatible with all versions of Veeam Backup & Replication, including v13 and earlier on Windows.

ConcurrencyInspectorv13Linux.ps1:
Designed specifically for Veeam Backup & Replication v13 installations on Linux.

WHAT THE SCRIPTS DO:

These scripts gather resource and configuration data from all key backup infrastructure components, including:

VMware Proxies
CDP Proxies
GP Proxies
Gateway Servers
Repository Servers
Backup Server
SQL Server

Utilizing the concurrent task limitations recommended in the Veeam User Guide, the scripts analyze each server’s assigned roles and current settings. For servers with multiple roles (e.g., a server acting as both Gateway and VMware Proxy), the scripts calculate the required RAM and CPU based on actual concurrent task configurations in the Veeam console. They then automatically compare the available hardware resources against requirements to determine whether each server’s configuration is optimized or suboptimal.

The script includes an optional built-in feature to rescan backup infrastructure components in order to detect any hardware changes on the servers. A rescan is not required for changes made within the Veeam console.

RESULTS:

The output includes:

Available RAM and CPU
Required RAM and CPU (based on current concurrent task settings)
Suggested concurrent task settings
Note: The suggested concurrent task setting is for informational purposes only. Since each server role has unique resource requirements, the scripts provide the minimum possible suggestion across different roles, rather than a definitive recommendation.

OUTPUT FILES:

Results are displayed immediately in the PowerShell console and exported to several CSV files:

RequirementsComparison.csv: Details for all backup components
SuboptimalConfiguration.csv: Servers with suboptimal configurations
OptimizedConfiguration.csv: Servers with optimized configurations
Repositories.csv, Proxies.csv, Gateways.csv, CDPProxies.csv, GPProxies.csv: Data segmented by role


USAGE
The scripts are designed to be executed on the Backup Server. Follow the relevant steps based on the operating system and Veeam version:

WINDOWS ENVIRONMENTS:

Script: ConcurrencyInspectorWindows.ps1

V13 INSTALLATIONS:

PowerShell 7 or higher is required.
If you do not have PowerShell 7 installed, download and install it from the official Microsoft documentation.
Note: PowerShell ISE is not supported in PowerShell v6 and above. Therefore, for v13 installations, the script will not run in ISE. Use PowerShell 7 to execute the script.
V12.3 or Earlier:
You can run the script in any PowerShell environment, including PowerShell 5.1 and ISE. However, for optimal performance, PowerShell 5.1 or 7 is recommended.
How to Download the Script:

Run one of the following commands in PowerShell to download the script to your current directory:


Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ibkor/Concurrency-Detector/main/ConcurrencyInspectorWindows.ps1" -OutFile "ConcurrencyInspectorWindows.ps1"

or


curl "https://raw.githubusercontent.com/ibkor/Concurrency-Detector/main/ConcurrencyInspectorWindows.ps1" -o "ConcurrencyInspectorWindows.ps1"

or, download manually from: https://github.com/ibkor/Concurrency-Detector

CONFIGURATION STEPS:

The script saves output files by default to the C:\temp\csv folder.
Ensure this folder exists, or modify the $ExportPath variable (line 2 in the script) to your preferred location and create that folder.
Execution:

For v13 Windows installations, use PowerShell 7 to run the script.
For v12.3 or earlier versions, any PowerShell version is supported, but PowerShell 5.1 or 7 is recommended for faster execution.


LINUX ENVIRONMENTS:

To run cmdlets on a Veeam Software Appliance, you need to enable SSH connections and root shell access and import the Veeam Backup PowerShell Module. Follow the instructions on the Veeam User Guide: Running Veeam PowerShell Session from Linux Machines.

Enable SSH connections and request root shell access. Approve with SO. 
Install the ASP.NET Core Runtime 8.0 environment or later:
dnf install aspnetcore-runtime-8.0 -y

Note: You do not need to run Import-Module or manually connect to the VBR Server, the script handles module imports and server connections automatically.

Default Execution and Output Location
By default, output files are saved under /tmp/csv. If you wish to use a different output location, modify the $ExportPath variable within the script (Line 2).

Preparing the Output Directory
If you are using the default output path, create the necessary directory with:


mkdir -p /tmp/csv

If you prefer to use a custom output path, update the $ExportPath variable in the script accordingly, and create your chosen directory.

If the veeamadmin user will execute the script remotely, use sudo and ensure correct permissions and ownership so that files are accessible and inherit the proper group. 


Below commands are informational only, set appropriate permissions as per your needs. 

If not added, Add veeamadmin to the required group
usermod -aG veeam-grp-admin veeamadmin

 Set ownership of the output directory
chown -R veeamadmin:veeam-grp-admin /tmp/csv 


Set appropriate permissions
chmod -R u+rwX,go+rX /tmp/csv 

 Ensure new files inherit the group 

chmod g+s /tmp/csv

(Replace /tmp/csv above with your custom directory path if not using the default.)

Downloading and Editing the Script
Navigate to your working directory (e.g., /tmp):

cd /tmp
Download the script:

curl -O https://raw.githubusercontent.com/ibkor/Concurrency-Detector/main/ConcurrencyInspectorv13Linux.ps1
or download manually from: https://github.com/ibkor/Concurrency-Detector/tree/main
Edit the script as needed:

Open the script and update$ExportPath variable (typically on line 2) if necessary. vi command can be used for the edits. 
Running the Script
Start PowerShell with pwsh command and run the script. 

