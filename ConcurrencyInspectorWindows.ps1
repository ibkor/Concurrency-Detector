 # This project is licensed under the MIT License - see the LICENSE file for details.
# Requires Run as Administrator

$ExportPath = "C:\temp\csv"   #change if needed

#Requirements as per Veeam User Guide - Verify them and change if needed

#VMware - Hyper-V Proxy Requirements:
$VPProxyRAMReq = 1    #1 GB per task
$VPProxyCPUReq = 0.5  #1 CPU core per 2 tasks

#General Purprose Proxy
$GPProxyRAMReq = 4  #4GB per task
$GPProxyCPUReq = 2   #2 CPU core per task

# Repository / Gateway Requirements:
$RepoGWRAMReq = 1    #1 GB per task
$RepoGWCPUReq = 0.5  #1 CPU core per 2 tasks

# CDP Proxy Requirements:
$CDPProxyRAMReq = 8    #8 GB
$CDPProxyCPUReq = 4    #4 CPU core 

$BackupServerInfo = Get-VBRBackupServerInfo

#Backup Server
if($BackupServerInfo.Build.Major -eq 13){
    $BSCPUReq = 8
    $BSRAMReq = 16
    } else {
    $BSCPUReq = 4
    $BSRAMReq = 8
    }

# SQL Server Requirements, if it is on the same server with any backup component.
$SQLRAMReq = 2    #2 GB, min.
$SQLCPUReq = 1    #1 CPU core  min.

$BackupServerName = [System.Net.Dns]::GetHostByName(($env:computerName)).HostName

#Connect to VBR
$creds = Get-Credential
Connect-VBRServer -Credential $creds -Server $BackupServerName

# Rescan all the host when needed
function Get-UserResponse {
    $validResponses = @('y', 'n')
    $response = ''

    # Keep asking for input until a valid response is received
    while ($true) {
        $promptMessage = "Would you like to rescan all hosts to ensure the hardware data is up-to-date? Please enter 'y' for yes or 'n' for no:"
        $response = Read-Host -Prompt $promptMessage

        if ($validResponses -contains $response) {
            return $response
        } else {
            Write-Host "Invalid input. Please enter 'y' or 'n'."
        }
    }
}

$userResponse = Get-UserResponse

# Check the user's response
if ($userResponse -eq 'y') {
    Write-Host "Rescanning all hosts... Please wait."
    Rescan-VBREntity -AllHosts -Wait
    Write-Host "Rescan complete. Proceeding with data retrieval."
} else {
    Write-Host "Skipping rescan. Using existing data."
}

function SafeValue($value) {
if ($null -eq $value) { 0 } else { $value }
}

#Get all VMware proxies
$VMwareProxies = Get-VBRViProxy

#Get all Hyper-V Off-Host proxies
$HyperVProxies = Get-VBRHvProxy

# Get all CDP proxies
$CDPProxies = Get-VBRCDPProxy

$VPProxies = $VMwareProxies + $HyperVProxies

# Get all VBR Repositories
$VBRRepositories = Get-VBRBackupRepository

#Get All GP Proxies
$GPProxies = Get-VBRNASProxyServer

$ProxyData = @()
$CDPProxyData = @()
$GWData = @()
$RepoData = @()
$GPProxyData = @()
$RequirementsComparison = @()
$hostRoles = @{}

#Get SQL Server Host
function Get-SqlSName {
    # Define registry paths and keys
    $basePath = "HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication"
    $databaseConfigurationPath = "$basePath\DatabaseConfigurations"
    $sqlActiveConfigurationKey = "SqlActiveConfiguration"
    $postgreSqlPath = "$databaseConfigurationPath\PostgreSql"
    $msSqlPath = "$databaseConfigurationPath\MsSql"
    $sqlServerNameKey = "SqlServerName"
    $sqlHostNameKey = "SqlHostName"
    $SQLSName = $null

    try {
        $SQLSName = (Get-ItemProperty -Path $basePath -Name $sqlServerNameKey -ErrorAction Stop).SqlServerName
    } catch {
        try {
            $sqlActiveConfig = Get-ItemProperty -Path $databaseConfigurationPath -Name $sqlActiveConfigurationKey -ErrorAction Stop
            $activeConfigValue = $sqlActiveConfig.$sqlActiveConfigurationKey

            if ($activeConfigValue -eq "PostgreSql") {
                $SQLSName = (Get-ItemProperty -Path $postgreSqlPath -Name $sqlHostNameKey -ErrorAction Stop).SqlHostName
            } else {
                $SQLSName = (Get-ItemProperty -Path $msSqlPath -Name $sqlServerNameKey -ErrorAction Stop).SqlServerName
            }
        } catch {
            Write-Error "Unable to retrieve SQL Server name from registry."
        }
    }

    If ($SQLSName -eq "localhost") {
        $SQLSName = $BackupServerName
    }
return $SQLSName
}

function ConverttoGB ($inBytes) {
    $inGB = [math]::Floor($inBytes / 1GB)
    return $inGB
}

# Function to ensure values are non-negative
function EnsureNonNegative {
    param (
        [int]$Value
    )
    
    if ($Value -lt 0) {
        return 0
    } else {
        return $Value
    }
}

#Gather GP Proxy Data
foreach ($GPProxy in $GPProxies) {
    $NrofGPProxyTasks = $GPProxy.ConcurrentTaskNumber
    $Serv = Get-VBRServer -Name $GPProxy.Server.Name
    $GPProxyCores = $Serv.GetPhysicalHost().HardwareInfo.CoresCount
    $GPProxyRAM = ConverttoGB($Serv.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
    
    $GPProxyDetails = [PSCustomObject]@{
        "GP Proxy Name"         = $GPProxy.Server.Name
        "GP Proxy Server"       = $GPProxy.Server.Name
        "GP Proxy Cores"        = $GPProxyCores
        "GP Proxy RAM (GB)"     = $GPProxyRAM        
        "GP Concurrent Tasks"   = $NrofGPProxyTasks
    }                        

    $GPProxyData += $GPProxyDetails

    # Track host roles with Proxy.Name
    if (-not $hostRoles.ContainsKey($GPProxy.Server.Name)) {
        $hostRoles[$GPProxy.Server.Name] = [ordered]@{
            "Roles" = @("GPProxy")
            "Names" = @($GPProxy.Server.Name) 
            "TotalTasks" = 0
            "Cores" = $GPProxyCores
            "RAM" = $GPProxyRAM
            "Task" = $NrofGPProxyTasks
            "TotalGPProxyTasks" = 0
        }
    } else {
        $hostRoles[$GPProxy.Server.Name].Roles += "GPProxy"
        $hostRoles[$GPProxy.Server.Name].Names += $GPProxy.Server.Name
    }
    $hostRoles[$GPProxy.Server.Name].TotalGPProxyTasks += $NrofGPProxyTasks
    $hostRoles[$GPProxy.Server.Name].TotalTasks += $NrofGPProxyTasks
}

# Gather VMware and Hyper-V Proxy Data
foreach ($Proxy in $VPProxies) {
    $NrofProxyTasks = $Proxy.MaxTasksCount
   try { $ProxyCores = $Proxy.GetPhysicalHost().HardwareInfo.CoresCount
    $ProxyRAM = ConverttoGB($Proxy.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal) }
    catch{
     $Server = Get-VBRServer -Name $Proxy.Name
            $ProxyCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
            $ProxyRAM = ConverttoGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
    }
    
    if ($proxy.Type -eq "Vi") { $proxytype = "VMware" } else {$proxytype = $proxy.Type}

    $ProxyDetails = [PSCustomObject]@{
        "Proxy Name"         = $Proxy.Name
        "Proxy Server"       = $Proxy.Host.Name
        "Type"               = $proxytype
        "Proxy Cores"        = $ProxyCores
        "Proxy RAM (GB)"     = $ProxyRAM        
        "Concurrent Tasks"   = $NrofProxyTasks
    }                       

    $ProxyData += $ProxyDetails

    # Track host roles with Proxy.Name
    if (-not $hostRoles.ContainsKey($Proxy.Host.Name)) {
        $hostRoles[$Proxy.Host.Name] = [ordered]@{
            "Roles" = @("Proxy")
            "Names" = @($Proxy.Name) 
            "TotalTasks" = 0
            "Cores" = $ProxyCores
            "RAM" = $ProxyRAM
            "TotalVpProxyTasks" = 0
        }
    } else {
        $hostRoles[$Proxy.Host.Name].Roles += "Proxy"
        $hostRoles[$Proxy.Host.Name].Names += $Proxy.Name
    }
    $hostRoles[$Proxy.Host.Name].TotalVpProxyTasks += $NrofProxyTasks
    $hostRoles[$Proxy.Host.Name].TotalTasks += $NrofProxyTasks
}

# Gather CDP Proxy Data
foreach ($CDPProxy in $CDPProxies) {
    $CDPServer = Get-VBRServer | Where-Object { $_.Id -eq $CDPProxy.ServerId }
    $CDPProxyCores = $CDPServer.GetPhysicalHost().HardwareInfo.CoresCount
    $CDPProxyRAM = ConverttoGB($CDPServer.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)
        
    $CDPProxyDetails = [PSCustomObject]@{
        "CDP Proxy Name"     = $CDPProxy.Name    
        "CDP Proxy Server"   = $CDPServer.Name
        "CDP Proxy Cores"    = $CDPProxyCores
        "CDP Proxy RAM (GB)" = $CDPProxyRAM
    }

    $CDPProxyData += $CDPProxyDetails

    # Track host roles with CDPServer.Name
    if (-not $hostRoles.ContainsKey($CDPServer.Name)) {
        $hostRoles[$CDPServer.Name] = [ordered]@{
            "Roles" = @("CDPProxy")
            "Names" = @($CDPServer.Name)  
            "TotalTasks" = 0
            "Cores" = $CDPProxyCores
            "RAM" = $CDPProxyRAM
            "TotalCDPProxyTasks" = 0
        }
    } else {
        $hostRoles[$CDPServer.Name].Roles += "CDPProxy"
        $hostRoles[$CDPServer.Name].Names += $CDPServer.Name 
    }
    $hostRoles[$CDPServer.Name].TotalCDPProxyTasks += 1
}

# Gather Repository and Gateway Data
foreach ($Repository in $VBRRepositories) {
    $NrofRepositoryTasks = $Repository.Options.MaxTaskCount
    $gatewayServers = $Repository.GetActualGateways()
    $NrofgatewayServers = $gatewayServers.Count

    if ($gatewayServers.Count -gt 0) {
        foreach ($gatewayServer in $gatewayServers) {
            $Server = Get-VBRServer -Name $gatewayServer.Name
            $GWCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
            $GWRAM = ConverttoGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

            $RepositoryDetails = [PSCustomObject]@{
                "Repository Name"   = $Repository.Name
                "Gateway Server"    = $gatewayServer.Name
                "Gateway Cores"     = $GWCores
                "Gateway RAM (GB)"  = $GWRAM        
                "Concurrent Tasks"  = $NrofRepositoryTasks / $NrofgatewayServers
            }                        
            $GWData += $RepositoryDetails

            # Track host roles
            if (-not $hostRoles.ContainsKey($gatewayServer.Name)) {
                $hostRoles[$gatewayServer.Name] = [ordered]@{
                    "Roles" = @("Gateway")
                    "Names" = @($gatewayServer.Name) 
                    "TotalTasks" = 0
                    "Cores" = $GWCores
                    "RAM" = $GWRAM
                    "TotalGWTasks" = 0
                }
            } else {
                $hostRoles[$gatewayServer.Name].Roles += "Gateway"
                $hostRoles[$gatewayServer.Name].Names += $Repository.Name
            }
                if ($NrofRepositoryTasks -ne -1) {

            $hostRoles[$gatewayServer.Name].TotalGWTasks += $NrofRepositoryTasks
            $hostRoles[$gatewayServer.Name].TotalTasks += $NrofRepositoryTasks
            }else {
             $hostRoles[$gatewayServer.Name].TotalGWTasks += 128
            $hostRoles[$gatewayServer.Name].TotalTasks += 128
            }
        }
    } else {
        # Handle the repository host
        $Server = Get-VBRServer -Name $Repository.Host.Name
        $RepoCores = $Server.GetPhysicalHost().HardwareInfo.CoresCount
        $RepoRAM = ConverttoGB($Server.GetPhysicalHost().HardwareInfo.PhysicalRAMTotal)

        $RepositoryDetails = [PSCustomObject]@{
            "Repository Name"   = $Repository.Name
            "Repository Server" = $Repository.Host.Name
            "Repository Cores"  = $RepoCores
            "Repository RAM (GB)" = $RepoRAM        
            "Concurrent Tasks"   = $NrofRepositoryTasks
        }            
        $RepoData += $RepositoryDetails

        # Track host roles
        if (-not $hostRoles.ContainsKey($Repository.Host.Name)) {
            $hostRoles[$Repository.Host.Name] = [ordered]@{
                "Roles" = @("Repository")
                "Names" = @($Repository.Name)
                "TotalTasks" = 0
                "Cores" = $RepoCores
                "RAM" = $RepoRAM
                "TotalRepoTasks" = 0
            }
        } else {
            $hostRoles[$Repository.Host.Name].Roles += "Repository"
            $hostRoles[$Repository.Host.Name].Names += $Repository.Name
        }
         if ($NrofRepositoryTasks -ne -1) {
        $hostRoles[$Repository.Host.Name].TotalRepoTasks += $NrofRepositoryTasks
        $hostRoles[$Repository.Host.Name].TotalTasks += $NrofRepositoryTasks
        } else {
         $hostRoles[$Repository.Host.Name].TotalRepoTasks += 128
        $hostRoles[$Repository.Host.Name].TotalTasks += 128
        }
    }
}

$hostRoles[$BackupServerName].Roles += ("BackupServer" -join ', ')

$SQLServer = Get-SqlSName
try {
    $hostRoles[$SQLServer].Roles += ("SQLServer" -join ', ')
} catch {
    Write-Host "SQLServer is $SQLServer."
    }   

# Calculate requirements based on aggregated resources for multi-role servers
foreach ($server in $hostRoles.GetEnumerator()) {
    $SuggestedTasksByCores = 0 
    $SuggestedTasksByRAM = 0
    $serverName = $server.Key

    $RequiredCores = [Math]::Ceiling(
        (SafeValue $server.Value.TotalRepoTasks)    * $RepoGWCPUReq +
        (SafeValue $server.Value.TotalGWTasks)      * $RepoGWCPUReq +
        (SafeValue $server.Value.TotalVpProxyTasks) * $VPProxyCPUReq +
        (SafeValue $server.Value.TotalGPProxyTasks)* $GPProxyCPUReq +
        (SafeValue $server.Value.TotalCDPProxyTasks)* $CDPProxyCPUReq
    )

    $RequiredRAM = [Math]::Ceiling(
        (SafeValue $server.Value.TotalRepoTasks)    * $RepoGWRAMReq +
        (SafeValue $server.Value.TotalGWTasks)      * $RepoGWRAMReq +
        (SafeValue $server.Value.TotalVpProxyTasks) * $VPProxyRAMReq +
        (SafeValue $server.Value.TotalGPProxyTasks)* $GPProxyRAMReq +
        (SafeValue $server.Value.TotalCDPProxyTasks)* $CDPProxyRAMReq
    )
  
    $coresAvailable = $server.Value.Cores
    $ramAvailable = $server.Value.RAM
    $totalTasks = $server.Value.TotalTasks
    
    #suggestion cores / RAM are only to calculate the suggested nr of tasks. 
    $SuggestionCores = $coresAvailable
    $SuggestionRAM = [Math]::Ceiling(
     (SafeValue $ramAvailable) -
     (SafeValue $server.Value.TotalGPProxyTasks*$GPProxyRAMReq) -
     (SafeValue $server.Value.TotalCDPProxyTasks*$CDPProxyRAMReq)
    )
   
    if ($serverName -contains $BackupServerName) {
        $RequiredCores += $BSCPUReq  #CPU core requirement for Backup Server added
        $RequiredRAM += $BSRAMReq    #RAM requirement for Backup Server added
        $SuggestionCores -= $BSCPUReq
        $SuggestionRAM -= $BSRAMReq
    }

    if ($SQLServer -eq $serverName) {
        $RequiredCores += $SQLCPUReq  #min CPU core requirement for SQL Server added
        $RequiredRAM += $SQLRAMReq    #min RAM requirement for SQL Server added
        $SuggestionCores -= $SQLCPUReq
        $SuggestionRAM -= $SQLRAMReq
    }

    $SuggestedTasksByCores += $SuggestionCores*2
    $SuggestedTasksByRAM += $SuggestionRAM  

    $NonNegativeCores = EnsureNonNegative($SuggestedTasksByCores)
    $NonNegativeRAM = EnsureNonNegative($SuggestedTasksByRAM)

    # Calculate the max suggested tasks using non-negative values
    $MaxSuggestedTasks = [Math]::Min($NonNegativeCores, $NonNegativeRAM)

    $RequirementComparison = [PSCustomObject]@{
        "Server"          = $serverName
        "Type"            = ($server.Value.Roles -join '/ ')
        "Required Cores"  = $RequiredCores
        "Available Cores" = $coresAvailable
        "Required RAM (GB)" = $RequiredRAM
        "Available RAM (GB)" = $ramAvailable
        "Concurrent Tasks" = $totalTasks
        "Suggested Tasks"  = $MaxSuggestedTasks
        "Names"           = ($server.Value.Names -join '/ ')
    }
    $RequirementsComparison += $RequirementComparison
}

# Output summary of Repositories, Proxies, and CDP Proxies found
Write-Host "$($RepoData.Count) Repositories Found:"
$RepoData | Format-Table

Write-Host "$($GWData.Count) Gateways found:"
$GWData | Format-Table 

Write-Host "$($ProxyData.Count) Proxies found:"
$ProxyData | Format-Table 

Write-Host "$($CDPProxyData.Count) CDP Proxies found:"
$CDPProxyData | Format-Table 

Write-Host "$($GPProxyData.Count) GP Proxies found:"
$GPProxyData | Format-Table 

# Detect and mention which hosts are used for multiple roles
$multiRoleServers = $hostRoles.GetEnumerator() | Where-Object { $_.Value.Roles.Count -gt 1 }

if ($multiRoleServers) {
    $multiRoleServers | ForEach-Object {
        Write-Host "$($_.Key) has roles: $($_.Value.Roles -join '/ ') - Names: $($_.Value.Names -join '/ ')"
    }
} else {
    Write-Host "No servers are being used for multiple roles."
}

# Output the requirements comparison
Write-Host "Requirements Comparison:"

# Separate the outputs into optimized, underconfigured, and suboptimal configurations based on the comparison
$OptimizedConfiguration = @()
$SuboptimalConfiguration = @()
$UnderconfiguredConfiguration = @()

foreach ($req in $RequirementsComparison) {

    if ($req."Concurrent Tasks" -le $req."Suggested Tasks" -or ($req.'Required RAM (GB)' -le $req.'Available RAM (GB)' -and $req.'Required Cores' -le $req.'Available Cores')) {
        $OptimizedConfiguration += $req
    } else {
        $SuboptimalConfiguration += $req
    }
}

# Display the Optimized Configuration
if ($OptimizedConfiguration.Count -gt 0) {
    Write-Host "Optimized Configuration:"
    $OptimizedConfiguration | Format-Table 
} else {
    Write-Host "No servers found with optimized configuration."
}


# Display the Suboptimal Configuration
if ($SuboptimalConfiguration.Count -gt 0) {
    Write-Host "Suboptimal Configuration:"
    $SuboptimalConfiguration | Format-Table 
} else {
    Write-Host "No servers found with suboptimal configuration."
}

# Exporting the data to CSV files
$RepoData | Export-Csv -Path "$ExportPath\Repositories.csv" -Delimiter "," -NoTypeInformation
$GWData | Export-Csv -Path "$ExportPath\Gateways.csv" -Delimiter "," -NoTypeInformation
$ProxyData | Export-Csv -Path "$ExportPath\Proxies.csv" -Delimiter "," -NoTypeInformation
$CDPProxyData | Export-Csv -Path "$ExportPath\CDPProxies.csv" -Delimiter "," -NoTypeInformation
$RequirementsComparison | Export-Csv -Path "$ExportPath\RequirementsComparison.csv" -Delimiter "," -NoTypeInformation

# Exporting the separated configurations to CSV files for optimized, underconfigured, and suboptimal
$OptimizedConfiguration | Export-Csv -Path "$ExportPath\OptimizedConfiguration.csv" -Delimiter "," -NoTypeInformation
$SuboptimalConfiguration | Export-Csv -Path "$ExportPath\SuboptimalConfiguration.csv" -Delimiter "," -NoTypeInformation

Write-Host "Data exported to CSV files successfully."   
